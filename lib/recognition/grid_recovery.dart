part of 'grouping.dart';

/// Optional geometric recovery; never fills empty cells or uses guessed words.
void _recoverBackDots(
  GroupingResult result,
  List<Detection> detections,
  int backClassId, {
  double tolerance = .18,
}) {
  if (!tolerance.isFinite || tolerance <= 0 || tolerance >= .5) {
    throw const FormatException('Invalid recovery tolerance');
  }
  final candidates = <_Record>[];
  for (var i = 0; i < detections.length; i++) {
    final d = detections[i];
    if (d.classId == backClassId &&
        [d.x1, d.y1, d.x2, d.y2, d.score].every((v) => v.isFinite) &&
        d.width > 0 &&
        d.height > 0 &&
        d.score >= 0 &&
        d.score <= 1 &&
        math.max(d.width, d.height) / math.min(d.width, d.height) <= 2.2) {
      candidates.add(_Record(d, i));
    }
  }
  result.rawCodes = [...result.codes];
  result.requiresReview = true;
  if (candidates.isEmpty || result.cells.isEmpty) return;
  final tree = _KdTree(candidates.map((c) => c.point).toList()),
      claims = <int, int>{};
  final proposals = <(Map<String, dynamic>, int, int, _Point)>[];
  _Point point(dynamic a) =>
      _Point((a[0] as num).toDouble(), (a[1] as num).toDouble());
  (_Point, _Point) frame(List<_Point> sites) => (
    _Point(
      _mean([for (var i = 0; i < 3; i++) sites[i + 3].x - sites[i].x]),
      _mean([for (var i = 0; i < 3; i++) sites[i + 3].y - sites[i].y]),
    ),
    ((sites[2] - sites[0]) + (sites[5] - sites[3])) * .25,
  );
  _Point? solve((_Point, _Point) f, _Point v) {
    final d = f.$1.x * f.$2.y - f.$2.x * f.$1.y;
    if (d.abs() < 1e-8) return null;
    return _Point(
      (v.x * f.$2.y - v.y * f.$2.x) / d,
      (f.$1.x * v.y - f.$1.y * v.x) / d,
    );
  }

  for (final cell in result.cells) {
    if (cell['code'] == '000000') continue;
    final anchors = <int, _Point>{};
    for (final neighbor in result.cells.where(
      (n) =>
          n['line'] == cell['line'] &&
          ((n['grid_column'] as int) - (cell['grid_column'] as int)).abs() <= 2,
    )) {
      final ids = neighbor['detections'] as List,
          residuals = neighbor['residuals'] as List;
      for (var i = 0; i < ids.length; i++) {
        anchors[ids[i] as int] = point(residuals[i]);
      }
    }
    if (anchors.length < 8) continue;
    final sx = result.grid['column_spacing'] as double,
        sy = result.grid['row_spacing'] as double;
    if (_median(
          anchors.values
              .map((p) => math.max((p.x / sx).abs(), (p.y / sy).abs()))
              .toList(),
        ) >
        .15) {
      continue;
    }
    final sites = (cell['sites'] as List).map(point).toList(), f = frame(sites);
    if (solve(f, const _Point(0, 0)) == null) continue;
    final reference = (cell['coarse_sites'] as List?)?.map(point).toList();
    final coarseFrame = reference == null ? null : frame(reference);
    final radius = .28 * (math.sqrt(f.$1.squared) + math.sqrt(f.$2.squared));
    final bits = (cell['code'] as String).split('');
    for (var bit = 0; bit < 6; bit++) {
      if (bits[bit] == '1') continue;
      final found = <(int, _Point)>[];
      for (final i in tree.within(sites[bit], radius)) {
        final residual = solve(f, candidates[i].point - sites[bit])!;
        var supported =
            math.max(residual.x.abs(), residual.y.abs()) <= tolerance;
        if (reference != null &&
            coarseFrame != null &&
            math.max(residual.x.abs(), residual.y.abs()) <= .28) {
          final coarse = solve(
            coarseFrame,
            candidates[i].point - reference[bit],
          );
          if (coarse != null &&
              math.max(coarse.x.abs(), coarse.y.abs()) <= tolerance) {
            supported = true;
          }
        }
        if (supported) {
          found.add((i, residual));
          claims[i] = (claims[i] ?? 0) + 1;
        }
      }
      if (found.length == 1) {
        proposals.add((cell, bit, found.first.$1, found.first.$2));
      }
    }
  }
  for (final (cell, bit, i, residual) in proposals) {
    if (claims[i] != 1) continue;
    final bits = (cell['code'] as String).split('')..[bit] = '1';
    cell.putIfAbsent('original_code', () => cell['code']);
    cell['code'] = bits.join();
    cell['requires_review'] = true;
    result.codes[cell['token_index'] as int] = bits.join();
    result.recoveredDots.add({
      'detection': candidates[i].index,
      'line': cell['line'],
      'column': cell['column'],
      'token_index': cell['token_index'],
      'dot': bit + 1,
      'original_class': backClassId,
      'residual': residual.list,
      'support': math.max(residual.x.abs(), residual.y.abs()) <= tolerance
          ? 'local'
          : 'coarse_and_local',
    });
  }
  if (result.recoveredDots.isNotEmpty) {
    result.warnings.add(
      'Recovered ${result.recoveredDots.length} back-labelled dots on front sites; classification recovery requires review',
    );
  }
}
