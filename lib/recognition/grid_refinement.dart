part of 'grouping.dart';

List<double> _lineBasis(double q, double row, double center, double scale) {
  final u = (q - center) / scale, v = row - 1;
  return [1, u, u * u, u * u * u, v, u * v];
}

double _interpolate(double q, List<double> knots, List<double> values) {
  if (q <= knots.first) return values.first;
  if (q >= knots.last) return values.last;
  var i = 0;
  while (i + 1 < knots.length && knots[i + 1] < q) {
    i++;
  }
  final fraction = (q - knots[i]) / (knots[i + 1] - knots[i]);
  return values[i] * (1 - fraction) + values[i + 1] * fraction;
}

class _LineModel {
  _LineModel(
    this.center,
    this.scale,
    this.coefficients,
    this.minCell,
    this.maxCell,
    this.trainingDots, {
    this.knots,
    this.offsets,
  });
  final double center, scale;
  final List<List<double>> coefficients;
  final int minCell, maxCell, trainingDots;
  final List<double>? knots;
  final List<_Point>? offsets;
  _Point site(double q, double row) {
    final b = _lineBasis(q, row, center, scale);
    var x = 0.0, y = 0.0;
    for (var i = 0; i < 6; i++) {
      x += b[i] * coefficients[i][0];
      y += b[i] * coefficients[i][1];
    }
    if (knots != null && offsets != null) {
      x += _interpolate(q, knots!, offsets!.map((p) => p.x).toList());
      y += _interpolate(q, knots!, offsets!.map((p) => p.y).toList());
    }
    return _Point(x, y);
  }

  Map<String, dynamic> toJson() => {
    'center': center,
    'scale': scale,
    'coefficients': coefficients,
    'min_cell': minCell,
    'max_cell': maxCell,
    'training_dots': trainingDots,
    if (knots != null) 'bend_knots': knots,
    if (offsets != null) 'bend_offsets': offsets!.map((p) => p.list).toList(),
  };
}

class _LocalFit {
  _LocalFit(
    this.models,
    this.fit,
    this.heldOut,
    this.changed,
    this.coarseResidual,
  );
  final Map<int, _LineModel> models;
  final _GridFit fit;
  final double heldOut;
  final int changed;
  final List<_Point> coarseResidual;
  Map<String, dynamic> toJson() => {
    'models': {for (final e in models.entries) '${e.key}': e.value.toJson()},
    'held_out_accepted_fraction': heldOut,
    'changed_assignments': changed,
  };
}

typedef _CoarseSite = _Point Function(double q, double row, int line);

_LineModel? _segmentedCandidate(
  List<_Point> points,
  List<double> q,
  List<double> rows,
  _LineModel model,
  _Point steps,
  double ratio,
) {
  final lo = q.reduce(math.min), hi = q.reduce(math.max);
  if (q.length < 30 || hi - lo < 8 * ratio) return null;
  final knots = _linspace(
    lo,
    hi,
    math.min(8, ((hi - lo) / (4 * ratio)).toInt() + 2),
  );
  final design = [
    for (final value in q)
      [
        for (var i = 0; i < knots.length; i++)
          _interpolate(
            value,
            knots,
            List.generate(knots.length, (j) => i == j ? 1.0 : 0.0),
          ),
      ],
  ];
  for (var i = 0; i < knots.length; i++) {
    if (design.fold<double>(0, (sum, r) => sum + r[i]) < 5) return null;
  }
  final residual = List.generate(
    q.length,
    (i) => points[i] - model.site(q[i], rows[i]),
  );
  var weights = List.filled(q.length, 1.0), offsets = <_Point>[];
  for (var iteration = 0; iteration < 4; iteration++) {
    final matrix = [
      for (var i = 0; i < q.length; i++)
        design[i].map((v) => v * math.sqrt(weights[i])).toList(),
    ];
    final target = [
      for (var i = 0; i < q.length; i++)
        (residual[i] * math.sqrt(weights[i])).list,
    ];
    for (var i = 0; i < knots.length; i++) {
      matrix.add(List.generate(knots.length, (j) => i == j ? .5 : 0.0));
      target.add([0, 0]);
    }
    for (var i = 0; i < knots.length - 2; i++) {
      matrix.add(
        List.generate(
          knots.length,
          (j) => j == i || j == i + 2 ? 2.0 : (j == i + 1 ? -4.0 : 0.0),
        ),
      );
      target.add([0, 0]);
    }
    final fit = _lstsq(matrix, target);
    if (fit == null) return null;
    offsets = fit.map((v) => _Point(v[0], v[1])).toList();
    weights = List.generate(q.length, (i) {
      var x = 0.0, y = 0.0;
      for (var j = 0; j < knots.length; j++) {
        x += design[i][j] * offsets[j].x;
        y += design[i][j] * offsets[j].y;
      }
      final error = math.sqrt(
        math.pow((x - residual[i].x) / steps.x, 2) +
            math.pow((y - residual[i].y) / steps.y, 2),
      );
      return math.min(1, .12 / math.max(error, 1e-8));
    });
  }
  if (offsets.any(
    (p) => math.max((p.x / steps.x).abs(), (p.y / steps.y).abs()) > .22,
  )) {
    return null;
  }
  return _LineModel(
    model.center,
    model.scale,
    model.coefficients,
    model.minCell,
    model.maxCell,
    model.trainingDots,
    knots: knots,
    offsets: offsets,
  );
}

bool _validLine(_LineModel model, _Point steps, double lo, double hi) {
  bool valid(_Point dq, _Point dr) =>
      dq.x >= .55 * steps.x &&
      dq.x <= 1.6 * steps.x &&
      dr.y >= .55 * steps.y &&
      dr.y <= 1.6 * steps.y &&
      dq.x * dr.y - dq.y * dr.x > 0;
  if (model.knots != null) {
    final qs = {
      ..._linspace(lo, hi, 100),
      ...model.knots!.map((v) => v - .001),
      ...model.knots!.map((v) => v + .001),
    }.toList()..sort();
    for (final row in [0.0, 1.0, 2.0]) {
      for (final q in qs) {
        final dq =
            (model.site(q + .0001, row) - model.site(q - .0001, row)) *
            (1 / .0002);
        final dr = model.site(q, row + .5) - model.site(q, row - .5);
        if (!valid(dq, dr)) return false;
      }
    }
  } else {
    final c = model.coefficients;
    for (final row in [-1.0, 0.0, 1.0]) {
      for (final q in _linspace(lo, hi, 24)) {
        final u = (q - model.center) / model.scale;
        final dq = _Point(
          (c[1][0] + 2 * u * c[2][0] + 3 * u * u * c[3][0] + row * c[5][0]) /
              model.scale,
          (c[1][1] + 2 * u * c[2][1] + 3 * u * u * c[3][1] + row * c[5][1]) /
              model.scale,
        );
        final dr = _Point(c[4][0] + u * c[5][0], c[4][1] + u * c[5][1]);
        if (!valid(dq, dr)) return false;
      }
    }
  }
  return true;
}

(List<double>, List<bool>) _lineEvidence(
  List<_Point> points,
  _LineModel model,
  double ratio,
  _Point steps,
  double tolerance,
) {
  final sites = [
    for (var cell = model.minCell; cell <= model.maxCell; cell++)
      for (var col = 0; col < 2; col++)
        for (var row = 0; row < 3; row++)
          model.site(cell * ratio + col, row.toDouble()),
  ];
  final tree = _KdTree(
    sites.map((p) => _Point(p.x / steps.x, p.y / steps.y)).toList(),
  );
  final residual = points.map((p) {
    final i = tree.nearest(_Point(p.x / steps.x, p.y / steps.y), 1).first;
    return _Point((p.x - sites[i].x) / steps.x, (p.y - sites[i].y) / steps.y);
  }).toList();
  return (
    residual.map((p) => math.min(p.squared, .5)).toList(),
    residual.map((p) => math.max(p.x.abs(), p.y.abs()) <= tolerance).toList(),
  );
}

_LocalFit? _refineLines(
  List<_Point> points,
  _GridFit coarse,
  List<bool> train,
  _Point ratios,
  _Point steps,
  double tolerance,
  _CoarseSite coarseSite, {
  bool refineSegments = false,
}) {
  var fit = _GridFit(
    [...coarse.ci],
    [...coarse.col],
    [...coarse.li],
    [...coarse.row],
    [...coarse.ex],
    [...coarse.ey],
    [...coarse.good],
  );
  final original = coarse, models = <int, _LineModel>{};
  final lines = {
    for (var i = 0; i < points.length; i++)
      if (fit.good[i]) fit.li[i],
  }.toList()..sort();
  for (final line in lines) {
    final cells = [
      for (var i = 0; i < points.length; i++)
        if (fit.li[i] == line && fit.good[i]) fit.ci[i],
    ];
    final lower = cells.reduce(math.min) - 1,
        upper = cells.reduce(math.max) + 1;
    if (upper - lower > 300) return null;
    final q = [
      for (var r = 0; r < 3; r++)
        ..._linspace(lower * ratios.x, upper * ratios.x + 1, 12),
    ];
    final rows = [for (var r = 0; r < 3; r++) ...List.filled(12, r.toDouble())];
    final center = _median(q),
        scale = math.max(q.reduce(math.max) - q.reduce(math.min), 1.0);
    final coeff = _lstsq(
      List.generate(q.length, (i) => _lineBasis(q[i], rows[i], center, scale)),
      List.generate(q.length, (i) => coarseSite(q[i], rows[i], line).list),
    );
    if (coeff == null) return null;
    models[line] = _LineModel(center, scale, coeff, lower, upper, 0);
  }
  if (models.isEmpty) return null;
  var active = models;
  for (var iteration = 0; iteration < 5; iteration++) {
    final fitted = {...active};
    for (final line in active.keys) {
      final mask = [
        for (var i = 0; i < points.length; i++)
          if (fit.li[i] == line && fit.good[i] && train[i]) i,
      ];
      if (mask.length < 12 ||
          mask.map((i) => fit.ci[i]).toSet().length < 4 ||
          mask.map((i) => fit.row[i]).toSet().length < 2) {
        continue;
      }
      final q = mask.map((i) => fit.ci[i] * ratios.x + fit.col[i]).toList(),
          rows = mask.map((i) => fit.row[i].toDouble()).toList();
      final center = _median(q),
          scale = math.max(q.reduce(math.max) - q.reduce(math.min), 1.0);
      final design = List.generate(
            q.length,
            (i) => _lineBasis(q[i], rows[i], center, scale),
          ),
          target = mask.map((i) => points[i]).toList();
      if (_lstsq(design, target.map((p) => p.list).toList()) == null) continue;
      var weights = List.filled(q.length, 1.0);
      List<List<double>>? coefficients;
      for (var robust = 0; robust < 5; robust++) {
        final prior = _lstsq(
          design,
          List.generate(
            q.length,
            (i) => active[line]!.site(q[i], rows[i]).list,
          ),
        );
        if (prior == null) return null;
        const penalty = [0.0, 0.0, .02, .04, 0.0, .02];
        final matrix = [
          for (var i = 0; i < q.length; i++)
            design[i].map((v) => v * math.sqrt(weights[i])).toList(),
        ];
        final targets = [
          for (var i = 0; i < q.length; i++)
            (target[i] * math.sqrt(weights[i])).list,
        ];
        for (var i = 0; i < 6; i++) {
          matrix.add(List.generate(6, (j) => i == j ? penalty[i] : 0.0));
          targets.add(prior[i].map((v) => v * penalty[i]).toList());
        }
        coefficients = _lstsq(matrix, targets);
        if (coefficients == null) return null;
        weights = List.generate(q.length, (i) {
          var x = 0.0, y = 0.0;
          for (var j = 0; j < 6; j++) {
            x += design[i][j] * coefficients![j][0];
            y += design[i][j] * coefficients[j][1];
          }
          final residual = math.sqrt(
            math.pow((x - target[i].x) / steps.x, 2) +
                math.pow((y - target[i].y) / steps.y, 2),
          );
          return math.min(1, .15 / math.max(residual, 1e-8));
        });
      }
      final cells = mask.map((i) => fit.ci[i]).toList(),
          lower = cells.reduce(math.min) - 1,
          upper = cells.reduce(math.max) + 1;
      if (upper - lower > 300) continue;
      final model = _LineModel(
            center,
            scale,
            coefficients!,
            lower,
            upper,
            mask.length,
          ),
          candidates = [model];
      if (refineSegments) {
        final segmented = _segmentedCandidate(
          target,
          q,
          rows,
          model,
          steps,
          ratios.x,
        );
        if (segmented != null) candidates.add(segmented);
      }
      for (final candidate in candidates) {
        if (!_validLine(
          candidate,
          steps,
          lower * ratios.x,
          upper * ratios.x + 1,
        )) {
          continue;
        }
        final check = [
              for (var i = 0; i < points.length; i++)
                if (fit.li[i] == line) i,
            ],
            held = check.map((i) => !train[i]).toList();
        if (held.where((v) => v).length < 3) continue;
        final before = _lineEvidence(
          check.map((i) => points[i]).toList(),
          fitted[line]!,
          ratios.x,
          steps,
          tolerance,
        );
        final after = _lineEvidence(
          check.map((i) => points[i]).toList(),
          candidate,
          ratios.x,
          steps,
          tolerance,
        );
        double loss(List<double> a, bool heldOut) => _mean([
          for (var i = 0; i < a.length; i++)
            if (held[i] == heldOut) a[i],
        ]);
        int accepted(List<bool> a) => [
          for (var i = 0; i < a.length; i++)
            if (held[i] && a[i]) i,
        ].length;
        if (loss(after.$1, false) < .95 * loss(before.$1, false) &&
            loss(after.$1, true) <=
                loss(before.$1, true) * (candidate.knots != null ? .95 : 1) &&
            accepted(after.$2) >= accepted(before.$2)) {
          fitted[line] = candidate;
        }
      }
    }
    final sites = <_Point>[], identities = <(int, int, int, int)>[];
    for (final entry in fitted.entries) {
      final model = entry.value;
      for (var cell = model.minCell; cell <= model.maxCell; cell++) {
        for (var col = 0; col < 2; col++) {
          for (var row = 0; row < 3; row++) {
            sites.add(model.site(cell * ratios.x + col, row.toDouble()));
            identities.add((cell, col, entry.key, row));
          }
        }
      }
    }
    if (sites.isEmpty) return null;
    final tree = _KdTree(
      sites.map((p) => _Point(p.x / steps.x, p.y / steps.y)).toList(),
    );
    final nearest = points
        .map((p) => tree.nearest(_Point(p.x / steps.x, p.y / steps.y), 1).first)
        .toList();
    final residual = List.generate(
      points.length,
      (i) => _Point(
        (points[i].x - sites[nearest[i]].x) / steps.x,
        (points[i].y - sites[nearest[i]].y) / steps.y,
      ),
    );
    fit = _GridFit(
      nearest.map((i) => identities[i].$1).toList(),
      nearest.map((i) => identities[i].$2).toList(),
      nearest.map((i) => identities[i].$3).toList(),
      nearest.map((i) => identities[i].$4).toList(),
      residual.map((p) => p.x).toList(),
      residual.map((p) => p.y).toList(),
      residual.map((p) => math.max(p.x.abs(), p.y.abs()) <= tolerance).toList(),
    );
    active = fitted;
  }
  final old = List.generate(points.length, (i) {
    final residual =
        points[i] -
        coarseSite(
          original.ci[i] * ratios.x + original.col[i],
          original.row[i].toDouble(),
          original.li[i],
        );
    return _Point(residual.x / steps.x, residual.y / steps.y);
  });
  final changed = List.generate(
    points.length,
    (i) =>
        original.ci[i] != fit.ci[i] ||
        original.col[i] != fit.col[i] ||
        original.li[i] != fit.li[i] ||
        original.row[i] != fit.row[i],
  );
  for (var i = 0; i < points.length; i++) {
    if (original.good[i] &&
        !changed[i] &&
        math.max(old[i].x.abs(), old[i].y.abs()) <= tolerance &&
        math.max(fit.ex[i].abs(), fit.ey[i].abs()) <= tolerance + .03) {
      fit.good[i] = true;
    }
  }
  final occupied = [
    for (var i = 0; i < points.length; i++)
      if (fit.good[i]) (fit.ci[i], fit.col[i], fit.li[i], fit.row[i]),
  ];
  if (occupied.length - occupied.toSet().length >
      math.max(2, .01 * occupied.length)) {
    return null;
  }
  final changedCount = [
    for (var i = 0; i < points.length; i++)
      if (fit.good[i] && changed[i]) i,
  ].length;
  if (occupied.isEmpty || changedCount / occupied.length > .20) return null;
  final held = _fraction([
    for (var i = 0; i < points.length; i++)
      if (!train[i]) fit.good[i],
  ]);
  return _LocalFit(active, fit, held, changedCount, old);
}
