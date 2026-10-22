import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'grouping.dart';
import 'translation.dart';
import 'vision.dart';

class ScanResult {
  const ScanResult(
    this.text,
    this.warnings,
    this.previewPath,
    this.seconds,
    this.dots,
    this.slices,
  );
  final String text, previewPath;
  final List<String> warnings;
  final double seconds;
  final int dots, slices;
}

class LocalRecognizer {
  Isolate? _worker;
  ReceivePort? _port;
  Completer<ScanResult>? _completion;
  bool _cancelled = false;

  Future<ScanResult> recognize(
    String image,
    void Function(String, double) onProgress,
  ) async {
    if (_completion != null) throw StateError('A scan is already running');
    _cancelled = false;
    final completion = _completion = Completer<ScanResult>();
    try {
      onProgress('Preparing offline models', 0);
      final directory = await getApplicationSupportDirectory();
      final modelPaths = <String>[];
      final metadata =
          jsonDecode(await rootBundle.loadString('assets/models/manifest.json'))
              as Map<String, dynamic>;
      for (final name in ['page', 'dots']) {
        final info = metadata['models'][name] as Map<String, dynamic>;
        final path = '${directory.path}/$name-${info['sha256']}.onnx';
        final file = File(path);
        if (!await file.exists() || await file.length() != info['bytes']) {
          final data = await rootBundle.load(info['asset'] as String);
          await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        }
        modelPaths.add(path);
      }
      if (_cancelled) return await completion.future;
      final temporary = await getTemporaryDirectory();
      final output =
          '${temporary.path}/scan-${DateTime.now().microsecondsSinceEpoch}';
      final port = _port = ReceivePort();
      port.listen((dynamic event) {
        if (completion.isCompleted) return;
        if (event is Map && event['type'] == 'progress') {
          onProgress(event['stage'] as String, event['fraction'] as double);
        } else if (event is Map && event['type'] == 'done') {
          completion.complete(
            ScanResult(
              event['text'] as String,
              (event['warnings'] as List).cast<String>(),
              event['preview'] as String,
              event['seconds'] as double,
              event['dots'] as int,
              event['slices'] as int,
            ),
          );
        } else if (event is Map && event['type'] == 'error') {
          completion.completeError(FormatException(event['message'] as String));
        } else if (event is List) {
          completion.completeError(
            StateError('Recognition stopped unexpectedly: ${event.first}'),
          );
        } else if (event == null) {
          completion.completeError(
            StateError('Recognition stopped before returning a result.'),
          );
        }
      });
      _worker = await Isolate.spawn(
        _recognizeWorker,
        {
          'port': port.sendPort,
          'source': image,
          'page': modelPaths[0],
          'dots': modelPaths[1],
          'output': output,
          'front': metadata['front_class_id'],
        },
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      if (_cancelled) _worker?.kill(priority: Isolate.immediate);
      return await completion.future;
    } finally {
      _worker?.kill(priority: Isolate.immediate);
      _worker = null;
      _port?.close();
      _port = null;
      _completion = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _worker?.kill(priority: Isolate.immediate);
    if (_completion case final completion? when !completion.isCompleted) {
      // Complete normally on cancellation to avoid an unobserved async error
      // while assets are still being copied. The screen discards this result.
      completion.complete(const ScanResult('', [], '', 0, 0, 0));
    }
  }
}

void _recognizeWorker(Map<String, dynamic> request) {
  final port = request['port'] as SendPort;
  final timer = Stopwatch()..start();
  void progress(String stage, double fraction) =>
      port.send({'type': 'progress', 'stage': stage, 'fraction': fraction});
  try {
    final vision = runVision(
      request['source'] as String,
      request['page'] as String,
      request['dots'] as String,
      request['output'] as String,
      progress,
    );
    File('${request['output']}/vision.json').writeAsStringSync(
      jsonEncode({
        'width': vision.width,
        'height': vision.height,
        'slices': vision.sliceCount,
        'detections': vision.detections.map((d) => d.toJson()).toList(),
      }),
    );
    progress('Grouping Braille cells', .9);
    final grouping = groupBraille(
      vision.detections,
      frontClassId: request['front'] as int,
    );
    if (grouping.codes.isEmpty) {
      throw const FormatException(
        'No usable front-side Braille dots found. Try a clear photo of the page.',
      );
    }
    progress('Translating into Sinhala', .97);
    final translation = translateBraille(grouping.codes);
    if (translation.text.trim().isEmpty) {
      throw const FormatException('No readable Braille text found.');
    }
    final warnings = [...grouping.warnings, ...translation.warnings];
    final result = {
      'type': 'done',
      'text': translation.text,
      'warnings': warnings,
      'preview': vision.previewPath,
      'seconds': timer.elapsedMilliseconds / 1000,
      'dots': vision.detections
          .where((d) => d.classId == request['front'])
          .length,
      'slices': vision.sliceCount,
    };
    File('${request['output']}/diagnostics.json').writeAsStringSync(
      jsonEncode({
        ...result,
        'image_width': vision.width,
        'image_height': vision.height,
        'codes': grouping.codes,
        'grouping': grouping.toJson(),
        'detections': vision.detections.map((d) => d.toJson()).toList(),
        'accepted_fraction': grouping.acceptedFraction,
      }),
    );
    port.send(result);
  } catch (error) {
    port.send({
      'type': 'error',
      'message': error is FormatException ? error.message : error.toString(),
    });
  }
}
