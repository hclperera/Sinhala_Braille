import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'detection.dart';

/// Native allocations are scoped explicitly; only one slice is inferred at once.
class YoloDetector {
  YoloDetector(String path, this.classes) : _net = cv.Net.fromOnnx(path);
  final cv.Net _net;
  final int classes;
  void dispose() => _net.dispose();

  List<Detection> detect(
    cv.Mat image, {
    double confidence = .25,
    double iou = .7,
    int maxDetections = 3500,
  }) {
    final owned = <cv.Mat>[];
    cv.Mat own(cv.Mat mat) {
      owned.add(mat);
      return mat;
    }

    final fill = cv.Scalar.all(114);
    try {
      final scale = math.min(640 / image.cols, 640 / image.rows);
      final width = (image.cols * scale).round(),
          height = (image.rows * scale).round();
      final left = ((640 - width) / 2 - .1).round();
      final top = ((640 - height) / 2 - .1).round();
      final resized = own(cv.resize(image, (width, height)));
      final padded = own(
        cv.copyMakeBorder(
          resized,
          top,
          640 - height - top,
          left,
          640 - width - left,
          cv.BORDER_CONSTANT,
          value: fill,
        ),
      );
      final blob = own(
        cv.blobFromImage(padded, scalefactor: 1 / 255, swapRB: true),
      );
      _net.setInput(blob);
      final prediction = own(_net.forward());
      final bytes = prediction.data;
      final values = Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
      const candidates = 8400;
      if (values.length != (classes + 4) * candidates) {
        throw const FormatException(
          'Unexpected model output. Re-export the bundled models.',
        );
      }
      final boxes = <Detection>[];
      for (var n = 0; n < candidates; n++) {
        var cls = 0, score = 0.0;
        for (var c = 0; c < classes; c++) {
          final value = values[(4 + c) * candidates + n];
          if (value > score) {
            score = value;
            cls = c;
          }
        }
        if (score < confidence) continue;
        final cx = values[n], cy = values[candidates + n];
        final w = values[2 * candidates + n], h = values[3 * candidates + n];
        boxes.add(
          Detection(
            cls,
            score,
            (cx - w / 2 - left) / scale,
            (cy - h / 2 - top) / scale,
            (cx + w / 2 - left) / scale,
            (cy + h / 2 - top) / scale,
          ),
        );
      }
      // YOLO performs NMS before clipping boxes to the source image.
      final selected = suppressDetections(
        boxes,
        threshold: iou,
        smallerArea: false,
        maxDetections: maxDetections,
      );
      return selected
          .map(
            (b) => Detection(
              b.classId,
              b.score,
              b.x1.clamp(0.0, image.cols.toDouble()),
              b.y1.clamp(0.0, image.rows.toDouble()),
              b.x2.clamp(0.0, image.cols.toDouble()),
              b.y2.clamp(0.0, image.rows.toDouble()),
            ),
          )
          .where((b) => b.area > 0)
          .toList();
    } finally {
      for (final mat in owned.reversed) {
        mat.dispose();
      }
      fill.dispose();
    }
  }
}

cv.Mat preprocessPage(cv.Mat page) {
  final gray = cv.cvtColor(page, cv.COLOR_BGR2GRAY);
  cv.Mat? smooth, enhanced;
  final clahe = cv.createCLAHE(clipLimit: 2, tileGridSize: (8, 8));
  try {
    smooth = cv.bilateralFilter(gray, 9, 75, 75);
    enhanced = clahe.apply(smooth);
    return cv.cvtColor(enhanced, cv.COLOR_GRAY2BGR);
  } finally {
    enhanced?.dispose();
    smooth?.dispose();
    gray.dispose();
    clahe.dispose();
  }
}

class VisionResult {
  const VisionResult(
    this.detections,
    this.width,
    this.height,
    this.previewPath,
    this.sliceCount,
  );
  final List<Detection> detections;
  final int width, height, sliceCount;
  final String previewPath;
}

VisionResult runVision(
  String source,
  String pageModel,
  String dotModel,
  String output,
  void Function(String, double) progress,
) {
  cv.setNumThreads(2);
  final owned = <cv.Mat>[];
  cv.Mat own(cv.Mat mat) {
    owned.add(mat);
    return mat;
  }

  YoloDetector? pageDetector, dotDetector;
  try {
    progress('Opening image', .02);
    // OpenCV IMREAD_COLOR honors EXIF orientation by default.
    final image = own(cv.imread(source, flags: cv.IMREAD_COLOR));
    if (image.isEmpty) {
      throw const FormatException(
        'This image could not be opened. Try a JPEG or PNG.',
      );
    }
    progress('Finding the page', .06);
    pageDetector = YoloDetector(pageModel, 1);
    final pages = pageDetector.detect(image, confidence: .6, maxDetections: 1);
    pageDetector.dispose();
    pageDetector = null;
    if (pages.isEmpty) {
      throw const FormatException(
        'No Braille page detected. Retake the photo with the entire page filling most of the frame.',
      );
    }
    final box = pages.first;
    final x = box.x1.floor(), y = box.y1.floor();
    final width = box.x2.ceil() - x, height = box.y2.ceil() - y;
    final rect = cv.Rect(x, y, width, height);
    final cv.Mat page;
    try {
      page = own(image.region(rect));
    } finally {
      rect.dispose();
    }
    progress('Enhancing contrast and reducing noise', .12);
    Directory(output).createSync(recursive: true);
    final preview = '$output/page.png';
    if (!cv.imwrite(preview, page)) {
      throw const FileSystemException('Could not save page preview');
    }
    final prepared = own(preprocessPage(page));
    final slices = imageSlices(width, height);
    dotDetector = YoloDetector(dotModel, 3);
    final predictions = <Detection>[];
    for (var i = 0; i < slices.length; i++) {
      progress(
        'Detecting dots · section ${i + 1} of ${slices.length}',
        .18 + .62 * i / slices.length,
      );
      final slice = slices[i];
      final sliceRect = cv.Rect(slice.x, slice.y, slice.width, slice.height);
      final cv.Mat tile;
      try {
        tile = prepared.region(sliceRect);
      } finally {
        sliceRect.dispose();
      }
      try {
        predictions.addAll(
          dotDetector.detect(tile).map((d) => d.shifted(slice.x, slice.y)),
        );
      } finally {
        tile.dispose();
      }
    }
    // SAHI does a standard pass when multiple slices are needed.
    if (slices.length > 1) {
      progress('Checking the full page', .81);
      predictions.addAll(dotDetector.detect(prepared));
    }
    progress('Merging overlapping detections', .86);
    // SAHI has no page-wide max_det cap. The 3500 cap applies per inference.
    final merged = suppressDetections(
      predictions,
      maxDetections: math.max(1, predictions.length),
    );
    return VisionResult(merged, width, height, preview, slices.length);
  } finally {
    pageDetector?.dispose();
    dotDetector?.dispose();
    for (final mat in owned.reversed) {
      mat.dispose();
    }
  }
}
