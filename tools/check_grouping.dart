import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:sinhala_braille/recognition/grouping.dart';
import 'package:sinhala_braille/recognition/detection.dart';

void main() {
  final cases =
      jsonDecode(File('test/fixtures/grouping_full.json').readAsStringSync())
          as List;
  for (final dynamic raw in cases) {
    final item = raw as Map<String, dynamic>, timer = Stopwatch()..start();
    final w = item['width'] as int, h = item['height'] as int;
    final detections = (item['detections'] as List).map((dynamic value) {
      final r = (value as List).cast<num>();
      return Detection(
        r[0].toInt(),
        r[5].toDouble(),
        (r[1] * w - r[3] * w / 2).toDouble(),
        (r[2] * h - r[4] * h / 2).toDouble(),
        (r[1] * w + r[3] * w / 2).toDouble(),
        (r[2] * h + r[4] * h / 2).toDouble(),
      );
    }).toList();
    GroupingResult? actual;
    try {
      actual = groupBraille(
        detections,
        config: GridConfig.fromJson(item['config'] as Map<String, dynamic>),
      );
    } on FormatException catch (error) {
      if (item['error'] == null) rethrow;
      stdout.writeln('PASS ${item['name']}: rejected (${error.message})');
      continue;
    }
    if (item['error'] != null) {
      throw StateError('${item['name']}: expected rejection');
    }
    final expected = item['expected'] as Map<String, dynamic>;
    if (jsonEncode(actual.codes) != jsonEncode(expected['codes'])) {
      throw StateError('${item['name']}: different Braille codes');
    }
    if (actual.grid['fit_type'] != (expected['grid'] as Map?)?['fit_type']) {
      throw StateError('${item['name']}: wrong grid type');
    }
    if (actual.requiresReview != (expected['requires_review'] ?? false)) {
      throw StateError('${item['name']}: review flag mismatch');
    }
    if (actual.recoveredDots.length !=
        (expected['recovered_dots'] as List? ?? []).length) {
      throw StateError('${item['name']}: recovery count differs');
    }
    final cells = expected['cells'] as List;
    if (actual.cells.length != cells.length) {
      throw StateError('${item['name']}: wrong cell count');
    }
    var maxSiteError = 0.0;
    for (var i = 0; i < cells.length; i++) {
      final a = actual.cells[i]['sites'] as List, b = cells[i]['sites'] as List;
      for (var dot = 0; dot < 6; dot++) {
        for (var axis = 0; axis < 2; axis++) {
          maxSiteError = math.max(
            maxSiteError,
            ((a[dot][axis] as num) - (b[dot][axis] as num)).abs().toDouble(),
          );
        }
      }
    }
    if (maxSiteError > .05) {
      throw StateError(
        '${item['name']}: diagnostic sites differ by $maxSiteError pixels',
      );
    }
    stdout.writeln(
      'PASS ${item['name']}: ${actual.grid['fit_type']}, ${timer.elapsedMilliseconds}ms, site delta ${maxSiteError.toStringAsFixed(6)}px',
    );
  }
  stdout.writeln('PASS: ${cases.length} complete-backend grouping cases.');
}
