/// Geometry port of Infox_Backend grouping r6.3. The frozen Python source and
/// revision are in tools/reference/. No language score participates in fitting.
library;

import 'dart:math' as math;
import 'detection.dart';
part 'grid_math.dart';
part 'grid_warp.dart';
part 'grid_refinement.dart';
part 'grid_recovery.dart';

const groupingVersion = '2026-10-18-r6.3-dart';

class GridConfig {
  factory GridConfig.fromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    (double, double) bounds(String key, (double, double) fallback) {
      final raw = json[key] as List?;
      return raw == null
          ? fallback
          : ((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }

    return GridConfig(
      frontClassId: json['front_class_id'] as int? ?? 2,
      backClassId: json['back_class_id'] as int? ?? 1,
      angleDegrees: number('angle_degrees'),
      columnSpacing: number('column_spacing'),
      rowSpacing: number('row_spacing'),
      cellPitch: number('cell_pitch'),
      linePitch: number('line_pitch'),
      xOrigin: number('x_origin'),
      yOrigin: number('y_origin'),
      tolerance: number('tolerance') ?? .28,
      maxAspectRatio: number('max_aspect_ratio') ?? 2.2,
      maxCellsPerLine: json['max_cells_per_line'] as int? ?? 300,
      fitMode: json['fit_mode'] as String? ?? 'auto',
      cellPitchBounds: bounds('cell_pitch_bounds', (2.05, 3.5)),
      linePitchBounds: bounds('line_pitch_bounds', (3.5, 5.5)),
      maxSpacingToDiameter: number('max_spacing_to_diameter') ?? 2.5,
      minAcceptedFraction: number('min_accepted_fraction') ?? .9,
      refineLines: json['refine_lines'] as bool? ?? false,
      refineSegments: json['refine_segments'] as bool? ?? false,
      recoverBackDots: json['recover_back_dots'] as bool? ?? false,
      preserveLeadingSpaces: json['preserve_leading_spaces'] as bool? ?? false,
    );
  }
  const GridConfig({
    this.frontClassId = 2,
    this.angleDegrees,
    this.columnSpacing,
    this.rowSpacing,
    this.cellPitch,
    this.linePitch,
    this.xOrigin,
    this.yOrigin,
    this.tolerance = .28,
    this.maxAspectRatio = 2.2,
    this.maxCellsPerLine = 300,
    this.fitMode = 'auto',
    this.cellPitchBounds = (2.05, 3.5),
    this.linePitchBounds = (3.5, 5.5),
    this.maxSpacingToDiameter = 2.5,
    this.minAcceptedFraction = .9,
    this.refineLines = false,
    this.refineSegments = false,
    this.recoverBackDots = false,
    this.backClassId = 1,
    this.preserveLeadingSpaces = false,
  });
  final int frontClassId, backClassId, maxCellsPerLine;
  final double? angleDegrees,
      columnSpacing,
      rowSpacing,
      cellPitch,
      linePitch,
      xOrigin,
      yOrigin;
  final double tolerance,
      maxAspectRatio,
      maxSpacingToDiameter,
      minAcceptedFraction;
  final String fitMode;
  final (double, double) cellPitchBounds, linePitchBounds;
  final bool refineLines,
      refineSegments,
      recoverBackDots,
      preserveLeadingSpaces;
  bool get calibrated => [
    columnSpacing,
    rowSpacing,
    cellPitch,
    linePitch,
    xOrigin,
    yOrigin,
  ].any((v) => v != null);
  void validate() {
    if (!(tolerance > 0 && tolerance < .5)) {
      throw const FormatException('Grid tolerance must lie between 0 and 0.5');
    }
    for (final pair in [(2, cellPitchBounds), (3, linePitchBounds)]) {
      if (!pair.$2.$1.isFinite ||
          !pair.$2.$2.isFinite ||
          pair.$2.$1 <= pair.$1 - 1 ||
          pair.$2.$1 >= pair.$2.$2) {
        throw const FormatException('Invalid grid pitch bounds');
      }
    }
    if (!maxSpacingToDiameter.isFinite ||
        maxSpacingToDiameter <= 0 ||
        !(minAcceptedFraction > .5 && minAcceptedFraction <= 1)) {
      throw const FormatException('Invalid grid quality settings');
    }
    if (!['auto', 'regular', 'warped'].contains(fitMode)) {
      throw const FormatException('Unknown grid fit mode');
    }
    if (recoverBackDots && backClassId == frontClassId) {
      throw const FormatException('Front and back classes must differ');
    }
  }
}

class GroupingResult {
  GroupingResult(
    this.codes,
    this.warnings,
    this.acceptedFraction, {
    List<Map<String, dynamic>>? cells,
    List<Map<String, dynamic>>? rejected,
    Map<String, dynamic>? grid,
  }) : cells = cells ?? [],
       rejected = rejected ?? [],
       grid = grid ?? {};
  final List<String> codes, warnings;
  final double acceptedFraction;
  final List<Map<String, dynamic>> cells, rejected;
  final Map<String, dynamic> grid;
  List<String>? rawCodes;
  final List<Map<String, dynamic>> recoveredDots = [];
  bool requiresReview = false;
  Map<String, dynamic> toJson() => {
    'version': groupingVersion,
    'codes': codes,
    'warnings': warnings,
    'cells': cells,
    'rejected': rejected,
    'grid': grid,
    'raw_codes': rawCodes,
    'requires_review': requiresReview,
    'recovered_dots': recoveredDots,
  };
}

class _Record {
  const _Record(this.detection, this.index);
  final Detection detection;
  final int index;
  _Point get point => _Point(detection.cx, detection.cy);
}

class _GridFit {
  _GridFit(this.ci, this.col, this.li, this.row, this.ex, this.ey, this.good);
  List<int> ci, col, li, row;
  List<double> ex, ey;
  List<bool> good;
}

double _angle(List<_Point> points, double diameter) {
  if (points.length < 6) return 0;
  final tree = _KdTree(points), angles = <double>[];
  for (var i = 0; i < points.length; i++) {
    for (final j
        in tree.nearest(points[i], math.min(18, points.length)).skip(1)) {
      final delta = points[j] - points[i];
      if (delta.x > diameter &&
          (delta.y / delta.x).abs() < math.tan(math.pi / 12)) {
        angles.add(math.atan2(delta.y, delta.x) * 180 / math.pi);
      }
    }
  }
  if (angles.isEmpty) return 0;
  final counts = List.filled(301, 0);
  for (final a in angles) {
    counts[((a + 15) / .1).floor().clamp(0, 300)]++;
  }
  var peak = 0;
  for (var i = 1; i < counts.length; i++) {
    if (counts[i] > counts[peak]) peak = i;
  }
  final center = -15 + peak * .1 + .05;
  return _median(angles.where((a) => (a - center).abs() < .2).toList());
}

GroupingResult groupBraille(
  List<Detection> detections, {
  int frontClassId = 2,
  GridConfig? config,
}) {
  final cfg = config ?? GridConfig(frontClassId: frontClassId);
  cfg.validate();
  final warnings = <String>[],
      rejected = <Map<String, dynamic>>[],
      records = <_Record>[],
      other = <_Point>[];
  for (var i = 0; i < detections.length; i++) {
    final d = detections[i];
    if (![d.x1, d.y1, d.x2, d.y2, d.score].every((v) => v.isFinite) ||
        d.width <= 0 ||
        d.height <= 0 ||
        d.score < 0 ||
        d.score > 1) {
      rejected.add({'index': i, 'reason': 'invalid detection'});
      continue;
    }
    if (d.classId != cfg.frontClassId) {
      other.add(_Point(d.cx, d.cy));
      continue;
    }
    if (math.max(d.width, d.height) / math.min(d.width, d.height) >
        cfg.maxAspectRatio) {
      rejected.add({'index': i, 'reason': 'aspect ratio'});
      continue;
    }
    records.add(_Record(d, i));
  }
  if (records.isEmpty) {
    return GroupingResult([], ['No front dots'], 0, rejected: rejected);
  }
  final diameter = _median(
    records.map((r) => math.sqrt(r.detection.area)).toList(),
  );
  if (other.isNotEmpty) {
    final tree = _KdTree(other);
    final conflicts = records
        .where(
          (r) =>
              (r.point - other[tree.nearest(r.point, 1).first]).squared <
              math.pow(.35 * diameter, 2),
        )
        .length;
    if (conflicts > 0) {
      warnings.add(
        '$conflicts front detections have near-coincident other-class detections; inspect classification',
      );
    }
  }
  var data = records.where((r) {
    final d = math.sqrt(r.detection.area),
        keep = d >= diameter * .35 && d <= diameter * 3.5;
    if (!keep) {
      rejected.add({'index': r.index, 'reason': 'relative size outlier'});
    }
    return keep;
  }).toList();
  if (data.isEmpty) {
    throw const FormatException(
      'All front detections failed relative-size filtering',
    );
  }
  final tree = _KdTree(data.map((r) => r.point).toList());
  final order = List.generate(data.length, (i) => i)
    ..sort((i, j) {
      final score = data[j].detection.score.compareTo(data[i].detection.score);
      return score != 0
          ? score
          : data[i].detection.area.compareTo(data[j].detection.area);
    });
  final suppressed = <int>{}, kept = <_Record>[];
  for (final i in order) {
    if (suppressed.contains(i)) {
      rejected.add({'index': data[i].index, 'reason': 'same-class duplicate'});
      continue;
    }
    kept.add(data[i]);
    suppressed.addAll(
      tree.within(data[i].point, .35 * diameter).where((j) => j != i),
    );
  }
  data = kept;
  final angle =
      cfg.angleDegrees ?? _angle(data.map((r) => r.point).toList(), diameter);
  if (!angle.isFinite) throw const FormatException('Grid angle must be finite');
  final theta = angle * math.pi / 180, c = math.cos(theta), s = math.sin(theta);
  _Point rotateBack(_Point p) => _Point(p.x * c - p.y * s, p.x * s + p.y * c);
  final points = data
      .map(
        (r) => _Point(
          r.point.x * c + r.point.y * s,
          -r.point.x * s + r.point.y * c,
        ),
      )
      .toList();
  late _GridFit fit;
  var x0 = 0.0,
      y0 = 0.0,
      dx = 1.0,
      dy = 1.0,
      px = 0.0,
      py = 0.0,
      xs = 0.0,
      ys = 0.0;
  _Warp? warp;
  _LocalFit? local;
  String? regularError;
  try {
    if (cfg.fitMode == 'warped') {
      throw const FormatException('Smooth page fitting explicitly selected');
    }
    final x = _fitAxis(
      points.map((p) => p.x).toList(),
      2,
      diameter,
      spacing: cfg.columnSpacing,
      pitch: cfg.cellPitch,
      origin: cfg.xOrigin,
      pitchBounds: cfg.cellPitchBounds,
      maxSpacingToDiameter: cfg.maxSpacingToDiameter,
    );
    final y = _fitAxis(
      points.map((p) => p.y).toList(),
      3,
      diameter,
      spacing: cfg.rowSpacing,
      pitch: cfg.linePitch,
      origin: cfg.yOrigin,
      pitchBounds: cfg.linePitchBounds,
      maxSpacingToDiameter: cfg.maxSpacingToDiameter,
    );
    x0 = x.origin;
    dx = x.gap;
    px = x.pitch;
    xs = x.score;
    y0 = y.origin;
    dy = y.gap;
    py = y.pitch;
    ys = y.score;
    final ax = points.map((p) => x.assign(p.x, 2)).toList(),
        ay = points.map((p) => y.assign(p.y, 3)).toList();
    fit = _GridFit(
      ax.map((a) => a.index).toList(),
      ax.map((a) => a.slot).toList(),
      ay.map((a) => a.index).toList(),
      ay.map((a) => a.slot).toList(),
      ax.map((a) => a.error).toList(),
      ay.map((a) => a.error).toList(),
      List.generate(
        points.length,
        (i) =>
            ax[i].error.abs() <= dx * cfg.tolerance &&
            ay[i].error.abs() <= dy * cfg.tolerance,
      ),
    );
    if ((cfg.refineLines || cfg.refineSegments) && points.length >= 30) {
      final train = List.filled(points.length, true);
      for (final line in fit.li.toSet()) {
        final indices =
            [
              for (var i = 0; i < points.length; i++)
                if (fit.li[i] == line) i,
            ]..sort((a, b) {
              final order = points[a].x.compareTo(points[b].x);
              return order != 0 ? order : points[a].y.compareTo(points[b].y);
            });
        for (var i = 0; i < indices.length; i += 5) {
          train[indices[i]] = false;
        }
      }
      try {
        final candidate = _refineLines(
          points,
          fit,
          train,
          _Point(px / dx, py / dy),
          _Point(dx, dy),
          cfg.tolerance,
          (q, row, line) => _Point(x0 + dx * q, y0 + py * line + dy * row),
          refineSegments: cfg.refineSegments,
        );
        if (candidate != null) {
          final old = List.generate(
            points.length,
            (i) => math
                .min(
                  math.pow(fit.ex[i] / dx, 2) + math.pow(fit.ey[i] / dy, 2),
                  .5,
                )
                .toDouble(),
          );
          final next = List.generate(
            points.length,
            (i) => math
                .min(
                  math.pow(candidate.fit.ex[i], 2) +
                      math.pow(candidate.fit.ey[i], 2),
                  .5,
                )
                .toDouble(),
          );
          double loss(List<double> a, bool flag) => _mean([
            for (var i = 0; i < a.length; i++)
              if (train[i] == flag) a[i],
          ]);
          final held = _fraction([
            for (var i = 0; i < train.length; i++)
              if (!train[i]) fit.good[i],
          ]);
          if (loss(next, true) < loss(old, true) &&
              loss(next, false) < loss(old, false) &&
              _fraction(candidate.fit.good) >=
                  math.max(_fraction(fit.good), cfg.minAcceptedFraction) &&
              candidate.heldOut >= math.max(held, cfg.minAcceptedFraction)) {
            local = candidate;
            fit = candidate.fit;
            fit.ex = fit.ex.map((v) => v * dx).toList();
            fit.ey = fit.ey.map((v) => v * dy).toList();
            warnings.add(
              'Used independently refined regular-grid lines; inspect cell boundaries',
            );
          }
        }
      } on FormatException {
        /* Optional refinement preserves the coarse fit. */
      }
    }
    if (_fraction(fit.good) < cfg.minAcceptedFraction) {
      throw FormatException(
        'Poor regular-grid fit (${(_fraction(fit.good) * 100).toStringAsFixed(1)}% accepted)',
      );
    }
  } on FormatException catch (error) {
    if (cfg.fitMode == 'regular' || cfg.calibrated) rethrow;
    regularError = error.message;
    final fitted = _fitWarp(points, diameter, cfg);
    fit = fitted.$1;
    warp = fitted.$2;
    local = null;
    x0 = y0 = 0;
    dx = dy = 1;
    px = warp.ratios.x;
    py = warp.ratios.y;
    xs = _mean(fit.ex.map((e) => math.min(e * e, .25)));
    ys = _mean(fit.ey.map((e) => math.min(e * e, .25)));
    warnings.add(
      'Used a smooth page warp after the regular grid failed; inspect cell boundaries',
    );
  }
  if (cfg.xOrigin == null || cfg.yOrigin == null) {
    warnings.add(
      'Automatically inferred lattice; verify its overlay before trusting sparse text',
    );
  }
  double extent(int axis) =>
      points.map((p) => p[axis]).reduce(math.max) -
      points.map((p) => p[axis]).reduce(math.min);
  if (warp == null && (extent(0) <= 1.3 * dx || extent(1) <= 2.3 * dy)) {
    warnings.add(
      'Isolated cell or line: repetition pitch is provisional; verify sparse text',
    );
  }
  final offGrid = fit.good.where((v) => !v).length;
  if (offGrid > 0) {
    warnings.add(
      '$offGrid off-grid detections excluded; inspect rejected dots',
    );
  }
  final cells = <(int, int), Map<int, Map<String, dynamic>>>{};
  for (var i = 0; i < data.length; i++) {
    final residual = [fit.ex[i], fit.ey[i]];
    if (!fit.good[i]) {
      rejected.add({
        'index': data[i].index,
        'reason': 'off grid',
        'residual': residual,
      });
      continue;
    }
    final slots = cells.putIfAbsent((fit.li[i], fit.ci[i]), () => {}),
        bit = fit.col[i] * 3 + fit.row[i];
    final rank = [
      math.pow(fit.ex[i] / dx, 2) + math.pow(fit.ey[i] / dy, 2),
      -data[i].detection.score,
      data[i].index,
    ];
    final candidate = <String, dynamic>{
      'index': data[i].index,
      'score': data[i].detection.score,
      'residual': residual,
      'rank': rank,
    };
    final previous = slots[bit];
    if (previous != null) {
      var better = false;
      for (var r = 0; r < 3; r++) {
        final order = (rank[r]).compareTo((previous['rank'] as List)[r] as num);
        if (order != 0) {
          better = order < 0;
          break;
        }
      }
      final loser = better ? previous : candidate;
      rejected.add({
        'index': loser['index'],
        'reason': 'slot collision',
        'residual': loser['residual'],
      });
      if (!better) continue;
    }
    slots[bit] = candidate;
  }
  final collisions = rejected
      .where((r) => r['reason'] == 'slot collision')
      .length;
  if (collisions > 0) {
    warnings.add(
      '$collisions duplicate slot assignments excluded from supporting evidence',
    );
  }
  final codes = <String>[], outputCells = <Map<String, dynamic>>[];
  if (cells.isNotEmpty) {
    final minLine = cells.keys.map((k) => k.$1).reduce(math.min),
        maxLine = cells.keys.map((k) => k.$1).reduce(math.max);
    if (maxLine - minLine > 500) {
      throw const FormatException('Implausible line count');
    }
    final globalMin = cells.keys.map((k) => k.$2).reduce(math.min);
    for (var line = minLine; line <= maxLine; line++) {
      final occupied =
          cells.keys.where((k) => k.$1 == line).map((k) => k.$2).toList()
            ..sort();
      if (occupied.isNotEmpty) {
        final lo = cfg.preserveLeadingSpaces ? globalMin : occupied.first,
            hi = occupied.last;
        if (hi - lo + 1 > cfg.maxCellsPerLine) {
          throw const FormatException('Implausible cell count; verify pitch');
        }
        for (var column = lo; column <= hi; column++) {
          final entry = cells[(line, column)],
              bits = List.generate(
                6,
                (b) => entry?.containsKey(b) == true ? '1' : '0',
              );
          final evidence = entry == null
              ? <Map<String, dynamic>>[]
              : (entry.keys.toList()..sort()).map((b) => entry[b]!).toList();
          var sites = [
            for (var col = 0; col < 2; col++)
              for (var row = 0; row < 3; row++)
                _Point(x0 + column * px + col * dx, y0 + line * py + row * dy),
          ];
          if (warp != null) sites = sites.map(warp.inverse).toList();
          List<List<double>>? coarse;
          final model = warp?.lineModels[line] ?? local?.models[line];
          if (model != null) {
            coarse = sites.map((p) => rotateBack(p).list).toList();
            final ratio = warp != null ? px : px / dx;
            sites = [
              for (var col = 0; col < 2; col++)
                for (var row = 0; row < 3; row++)
                  model.site(column * ratio + col, row.toDouble()),
            ];
          }
          outputCells.add({
            'line': line - minLine,
            'column': column - lo,
            'grid_column': column,
            'code': bits.join(),
            'token_index': codes.length,
            'sites': sites.map((p) => rotateBack(p).list).toList(),
            'coarse_sites': coarse,
            'detections': evidence.map((e) => e['index']).toList(),
            'min_score': evidence.isEmpty
                ? null
                : evidence.map((e) => e['score'] as double).reduce(math.min),
            'residuals': evidence.map((e) => e['residual']).toList(),
          });
          codes.add(bits.join());
        }
      }
      codes.add('\n');
    }
  }
  final accepted = _fraction(fit.good),
      result = GroupingResult(
        codes,
        warnings,
        accepted,
        cells: outputCells,
        rejected: rejected,
        grid: {
          'fit_type': warp == null ? 'regular' : 'warped',
          'coordinate_units': warp == null ? 'pixels' : 'dot steps',
          'warp': warp?.toJson(),
          'regular_fit_failure': regularError,
          'line_refinement': local?.toJson(),
          'angle_degrees': angle,
          'x_origin': x0,
          'y_origin': y0,
          'column_spacing': dx,
          'row_spacing': dy,
          'cell_pitch': px,
          'line_pitch': py,
          'x_fit_error': xs,
          'y_fit_error': ys,
          'accepted_fraction': accepted,
          'retained_detection_count': data.length,
          'unique_slot_count': cells.values.fold<int>(
            0,
            (n, c) => n + c.length,
          ),
          'slot_collision_count': collisions,
          'unique_slot_fraction':
              (fit.good.where((v) => v).length - collisions) / data.length,
        },
      );
  if (cfg.recoverBackDots) {
    _recoverBackDots(result, detections, cfg.backClassId);
  }
  if (cfg.refineSegments) {
    result.requiresReview = true;
    warnings.add(
      'Experimental within-line bend refinement requested; review text before use',
    );
  }
  return result;
}
