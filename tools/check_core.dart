// Pure Dart reference checks, runnable without Android or native libraries.
import 'dart:convert';
import 'dart:io';
import 'package:sinhala_braille/recognition/detection.dart';
import 'package:sinhala_braille/recognition/grouping.dart';
import 'package:sinhala_braille/recognition/translation.dart';

void main() {
  final fixtures =
      jsonDecode(File('test/fixtures/reference.json').readAsStringSync())
          as Map<String, dynamic>;
  var count = 0;
  for (final fixture in fixtures['translation'] as List) {
    final actual = translateBraille(
      (fixture['codes'] as List).cast<String>(),
    ).text;
    if (actual != fixture['text']) {
      throw StateError(
        'Translation mismatch: ${fixture['codes']} expected ${fixture['text']} got $actual',
      );
    }
    count++;
  }
  for (final fixture in fixtures['slices'] as List) {
    final actual = imageSlices(
      fixture['width'] as int,
      fixture['height'] as int,
    ).map((s) => [s.x, s.y, s.x + s.width, s.y + s.height]).toList();
    if (jsonEncode(actual) != jsonEncode(fixture['boxes'])) {
      throw StateError('SAHI slicing mismatch: $fixture');
    }
    count++;
  }
  for (final fixture in fixtures['grouping'] as List) {
    final width = fixture['width'] as int, height = fixture['height'] as int;
    final detections = (fixture['detections'] as List).map((dynamic raw) {
      final row = (raw as List).cast<num>();
      final x = row[1] * width, y = row[2] * height;
      final w = row[3] * width, h = row[4] * height;
      return Detection(
        row[0].toInt(),
        row[5].toDouble(),
        (x - w / 2).toDouble(),
        (y - h / 2).toDouble(),
        (x + w / 2).toDouble(),
        (y + h / 2).toDouble(),
      );
    }).toList();
    final result = groupBraille(detections);
    if (jsonEncode(result.codes) != jsonEncode(fixture['codes'])) {
      throw StateError(
        'Grid mismatch at angle ${fixture['angle']}: ${result.codes} / ${fixture['codes']}',
      );
    }
    count++;
  }
  const high = Detection(2, .95, 0, 0, 10, 10);
  const inside = Detection(2, .8, 2, 2, 6, 6);
  const back = Detection(1, .9, 2, 2, 6, 6);
  if (suppressDetections([inside, high, back]).length != 2) {
    throw StateError('Class-aware IOS merging failed');
  }
  if (suppressDetections(
        [inside, high],
        threshold: .7,
        smallerArea: false,
      ).length !=
      2) {
    throw StateError('IoU suppression incorrectly used IOS');
  }
  stdout.writeln(
    'PASS: $count Python-reference cases plus class-aware IOS/IoU checks.',
  );
}
