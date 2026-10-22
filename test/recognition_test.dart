import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinhala_braille/recognition/detection.dart';
import 'package:sinhala_braille/recognition/grouping.dart';
import 'package:sinhala_braille/recognition/translation.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/reference.json').readAsStringSync())
          as Map<String, dynamic>;
  test('Sinhala decoding matches upstream Python reference', () {
    for (final row in fixture['translation'] as List) {
      expect(
        translateBraille((row['codes'] as List).cast<String>()).text,
        row['text'],
        reason: '${row['codes']}',
      );
    }
  });
  test(
    'Slicing matches SAHI, including partial images and final edge tiles',
    () {
      for (final row in fixture['slices'] as List) {
        expect(
          imageSlices(
            row['width'] as int,
            row['height'] as int,
          ).map((s) => [s.x, s.y, s.x + s.width, s.y + s.height]).toList(),
          row['boxes'],
        );
      }
    },
  );
  test('Cross-slice NMS uses IOS and keeps different classes', () {
    const front = Detection(2, .95, 0, 0, 10, 10);
    const contained = Detection(2, .8, 2, 2, 6, 6);
    const back = Detection(1, .9, 2, 2, 6, 6);
    expect(suppressDetections([front, contained, back]), [front, back]);
    expect(
      suppressDetections(
        [front, contained],
        threshold: .7,
        smallerArea: false,
      ).length,
      2,
    );
  });
  test('Back-side dots cannot produce Sinhala cells', () {
    expect(
      groupBraille([const Detection(1, .99, 10, 10, 16, 16)]).codes,
      isEmpty,
    );
  });
  test('Malformed cell does not consume a following valid consonant', () {
    expect(translateBraille(['000100', 'bad', '101000']).text, '��ක');
  });
}
