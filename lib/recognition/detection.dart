import 'dart:math' as math;

/// Coordinates are in the cropped page, unless explicitly local to a slice.
class Detection {
  const Detection(this.classId, this.score, this.x1, this.y1, this.x2, this.y2);
  final int classId;
  final double score, x1, y1, x2, y2;
  double get width => x2 - x1;
  double get height => y2 - y1;
  double get cx => (x1 + x2) / 2;
  double get cy => (y1 + y2) / 2;
  double get area => math.max(0, width) * math.max(0, height);
  Detection shifted(int x, int y) =>
      Detection(classId, score, x1 + x, y1 + y, x2 + x, y2 + y);
  Map<String, Object> toJson() => {
    'class': classId,
    'score': score,
    'box': [x1, y1, x2, y2],
  };
}

class ImageSlice {
  const ImageSlice(this.x, this.y, this.width, this.height);
  final int x, y, width, height;
}

/// SAHI's final edge slices are shifted back to retain their full size.
List<ImageSlice> imageSlices(
  int width,
  int height, {
  int size = 640,
  double overlap = .2,
}) {
  if (width <= 0 || height <= 0 || size <= 0 || overlap < 0 || overlap >= 1) {
    throw ArgumentError('Invalid image or slicing settings');
  }
  List<int> starts(int length) {
    final result = <int>[];
    final step = size - (size * overlap).toInt();
    var position = 0;
    while (true) {
      final start = math.max(0, math.min(position, length - size));
      if (result.isEmpty || result.last != start) result.add(start);
      if (start + size >= length) break;
      position += step;
    }
    return result;
  }

  return [
    for (final y in starts(height))
      for (final x in starts(width))
        ImageSlice(x, y, math.min(size, width - x), math.min(size, height - y)),
  ];
}

double overlapRatio(Detection a, Detection b, {bool smallerArea = false}) {
  final intersection =
      math.max(0.0, math.min(a.x2, b.x2) - math.max(a.x1, b.x1)) *
      math.max(0.0, math.min(a.y2, b.y2) - math.max(a.y1, b.y1));
  final denominator = smallerArea
      ? math.min(a.area, b.area)
      : a.area + b.area - intersection;
  return denominator > 0 ? intersection / denominator : 0;
}

/// Per-inference YOLO NMS uses IoU; cross-slice SAHI NMS uses IOS.
List<Detection> suppressDetections(
  List<Detection> input, {
  double threshold = .3,
  bool smallerArea = true,
  int maxDetections = 3500,
}) {
  final ranked = input.where((d) => d.area > 0 && d.score.isFinite).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  final kept = <Detection>[];
  for (final candidate in ranked) {
    if (!kept.any(
      (previous) =>
          previous.classId == candidate.classId &&
          overlapRatio(previous, candidate, smallerArea: smallerArea) >=
              threshold,
    )) {
      kept.add(candidate);
      if (kept.length >= maxDetections) break;
    }
  }
  return kept;
}
