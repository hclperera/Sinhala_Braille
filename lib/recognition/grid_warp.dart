part of 'grouping.dart';

List<double> _features(_Point point, _Point center, _Point span) {
  final u = (point.x - center.x) / span.x, v = (point.y - center.y) / span.y;
  final u2 = u * u, v2 = v * v, u3 = u * u * u, v3 = v * v * v;
  return [
    1,
    u,
    v,
    u2,
    u * v,
    v2,
    u3,
    u2 * v,
    u * v2,
    v3,
    u3 * u,
    u3 * v,
    u2 * v2,
    u * v3,
    v3 * v,
  ];
}

(List<double>, List<double>) _derivatives(
  _Point point,
  _Point center,
  _Point span,
) {
  final u = (point.x - center.x) / span.x,
      v = (point.y - center.y) / span.y,
      u2 = u * u,
      v2 = v * v;
  return (
    [
      0.0,
      1.0,
      0.0,
      2 * u,
      v,
      0.0,
      3 * u2,
      2 * u * v,
      v2,
      0.0,
      4 * u2 * u,
      3 * u2 * v,
      2 * u * v2,
      v2 * v,
      0.0,
    ].map((n) => n / span.x).toList(),
    [
      0.0,
      0.0,
      1.0,
      0.0,
      u,
      2 * v,
      0.0,
      u2,
      2 * u * v,
      3 * v2,
      0.0,
      u2 * u,
      2 * u2 * v,
      3 * u * v2,
      4 * v2 * v,
    ].map((n) => n / span.y).toList(),
  );
}

class _Warp {
  _Warp(
    this.center,
    this.span,
    this.coefficients,
    this.ratios,
    this.steps,
    this.heldOut,
    this.heldOutCount,
  );
  final _Point center, span, ratios, steps;
  final List<List<double>> coefficients;
  final double heldOut;
  final int heldOutCount;
  Map<int, _LineModel> lineModels = {};
  int? locallyReassigned;
  Map<String, dynamic>? localQuality;
  _Point forward(_Point p) {
    final f = _features(p, center, span);
    var x = 0.0, y = 0.0;
    for (var i = 0; i < 15; i++) {
      x += f[i] * coefficients[i][0];
      y += f[i] * coefficients[i][1];
    }
    return _Point(x, y);
  }

  (_Point, _Point) jacobian(_Point p) {
    final (fx, fy) = _derivatives(p, center, span);
    var xx = 0.0, xy = 0.0, yx = 0.0, yy = 0.0;
    for (var i = 0; i < 15; i++) {
      xx += fx[i] * coefficients[i][0];
      xy += fx[i] * coefficients[i][1];
      yx += fy[i] * coefficients[i][0];
      yy += fy[i] * coefficients[i][1];
    }
    return (_Point(xx, xy), _Point(yx, yy));
  }

  _Point inverse(_Point target) {
    final a = coefficients[1],
        b = coefficients[2],
        tx = target.x - coefficients[0][0],
        ty = target.y - coefficients[0][1];
    final determinant = a[0] * b[1] - a[1] * b[0];
    if (determinant.abs() < 1e-14) {
      throw const FormatException('Could not invert fitted grid');
    }
    var p =
        center +
        _Point(
          (tx * b[1] - ty * b[0]) / determinant * span.x,
          (a[0] * ty - a[1] * tx) / determinant * span.y,
        );
    for (var iteration = 0; iteration < 15; iteration++) {
      final error = forward(p) - target;
      if (math.max(error.x.abs(), error.y.abs()) < 1e-7) break;
      final (jx, jy) = jacobian(p);
      final det = jx.x * jy.y - jy.x * jx.y;
      if (det.abs() < 1e-14) {
        throw const FormatException('Could not invert fitted grid');
      }
      p =
          p -
          _Point(
            (error.x * jy.y - error.y * jy.x) / det,
            (jx.x * error.y - jx.y * error.x) / det,
          );
    }
    final error = forward(p) - target;
    if (!p.x.isFinite ||
        !p.y.isFinite ||
        math.max(error.x.abs(), error.y.abs()) > .01) {
      throw const FormatException(
        'Could not locate fitted cell sites reliably',
      );
    }
    return p;
  }

  Map<String, dynamic> toJson() => {
    'center': center.list,
    'span': span.list,
    'coefficients': coefficients,
    'periods_in_dot_steps': ratios.list,
    'local_spacing_px': steps.list,
    'held_out_accepted_fraction': heldOut,
    'held_out_count': heldOutCount,
    'line_refinement_candidate': localQuality,
    if (lineModels.isNotEmpty)
      'line_models': {
        for (final e in lineModels.entries) '${e.key}': e.value.toJson(),
      },
    if (locallyReassigned != null) 'locally_reassigned_dots': locallyReassigned,
  };
}

_Point _localSpacings(List<_Point> points, double diameter) {
  final tree = _KdTree(points), distances = [<double>[], <double>[]];
  for (final p in points) {
    for (final index in tree.nearest(p, math.min(12, points.length)).skip(1)) {
      final delta = points[index] - p;
      for (var axis = 0; axis < 2; axis++) {
        final along = delta[axis].abs(), across = delta[1 - axis].abs();
        if (along > .8 * diameter &&
            along < 2.2 * diameter &&
            across < .4 * diameter) {
          distances[axis].add(along);
        }
      }
    }
  }
  final steps = <double>[];
  for (final values in distances) {
    if (values.length < 20) {
      throw const FormatException(
        'Too few local pairs to estimate a curved-page grid',
      );
    }
    const bins = 89;
    final counts = List.filled(bins, 0.0), width = 1.4 * diameter / bins;
    for (final v in values) {
      counts[((v - .8 * diameter) / width).floor().clamp(0, bins - 1)]++;
    }
    // scipy.ndimage.gaussian_filter1d(sigma=2, truncate=4, mode='reflect').
    final kernel = [for (var i = -8; i <= 8; i++) math.exp(-i * i / 8)],
        sum = kernel.reduce((a, b) => a + b);
    final smoothed = List.filled(bins, 0.0);
    for (var i = 0; i < bins; i++) {
      for (var j = -8; j <= 8; j++) {
        var index = i + j;
        if (index < 0) index = -index - 1;
        if (index >= bins) index = 2 * bins - index - 1;
        smoothed[i] += counts[index] * kernel[j + 8] / sum;
      }
    }
    var peak = 0;
    for (var i = 1; i < bins; i++) {
      if (smoothed[i] > smoothed[peak]) peak = i;
    }
    final location = .8 * diameter + (peak + .5) * width;
    steps.add(
      _median(
        values.where((d) => (d - location).abs() < .12 * diameter).toList(),
      ),
    );
  }
  return _Point(steps[0], steps[1]);
}

(List<double>, double) _warpAxis(
  List<_Point> points,
  int axis,
  double diameter,
  double spacing,
  _Point center,
  _Point span,
  List<bool> train,
  (double, double) bounds,
  double tolerance,
) {
  final features = points.map((p) => _features(p, center, span)).toList();
  final seeds = <(_Point, double)>[
    for (final f in [.20, .28, .36]) (center, f),
    for (final offset in [
      (-.2, -.2),
      (.2, -.2),
      (-.2, .2),
      (.2, .2),
      (0.0, -.25),
      (0.0, .25),
    ])
      (center + _Point(span.x * offset.$1, span.y * offset.$2), .32),
  ];
  List<double>? bestCoefficients;
  var bestRatio = 0.0, bestAccepted = -1.0, bestScore = double.infinity;
  for (final (anchor, seedFraction) in seeds) {
    bool inside(int i, double fraction) =>
        train[i] &&
        (points[i].x - anchor.x).abs() < span.x * fraction / 2 &&
        (points[i].y - anchor.y).abs() < span.y * fraction / 2;
    final seed = [
      for (var i = 0; i < points.length; i++)
        if (inside(i, seedFraction)) points[i][axis],
    ];
    if (seed.length < 24) continue;
    final _Axis initial;
    try {
      initial = _fitAxis(
        seed,
        axis + 2,
        diameter,
        spacing: spacing,
        pitchBounds: bounds,
        refineSpacing: true,
      );
    } on FormatException {
      continue;
    }
    if (initial.score > .045) continue;
    final ratio = initial.pitch / initial.gap;
    var coefficients = List.filled(15, 0.0);
    coefficients[0] = (center[axis] - initial.origin) / initial.gap;
    coefficients[axis + 1] = span[axis] / initial.gap;
    for (final fraction in _linspace(seedFraction, 1.65, 40)) {
      final region = [
        for (var i = 0; i < points.length; i++)
          if (inside(i, fraction)) i,
      ];
      final count = fraction < .45 ? 6 : (fraction < .70 ? 10 : 15);
      for (var iteration = 0; iteration < 6; iteration++) {
        final good = <int>[], targets = <List<double>>[];
        for (final i in region) {
          final assigned = _assign(
            _dot(features[i], coefficients),
            0,
            1,
            ratio,
            axis + 2,
          );
          if (assigned.error.abs() < .32) {
            good.add(i);
            targets.add([assigned.slot + assigned.index * ratio]);
          }
        }
        if (good.length < math.max(20, 3 * count)) break;
        final matrix = good.map((i) => features[i].sublist(0, count)).toList();
        // Rank check is performed before regularization, exactly as upstream.
        if (_lstsq(matrix, targets) == null) break;
        for (var i = 3; i < count; i++) {
          matrix.add(List.generate(count, (j) => j == i ? .03 : 0.0));
          targets.add([0]);
        }
        final fitted = _lstsq(matrix, targets);
        if (fitted == null) break;
        final candidate = [...coefficients];
        for (var i = 0; i < count; i++) {
          candidate[i] = fitted[i][0];
        }
        var valid = true;
        for (final i in region) {
          final derivatives = _derivatives(points[i], center, span);
          final derivative = _dot(
            axis == 0 ? derivatives.$1 : derivatives.$2,
            candidate,
          );
          if (derivative < .5 / spacing || derivative > 1.6 / spacing) {
            valid = false;
            break;
          }
        }
        if (!valid) break;
        coefficients = candidate;
      }
    }
    final minX = points.map((p) => p.x).reduce(math.min),
        maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min),
        maxY = points.map((p) => p.y).reduce(math.max);
    var valid = true;
    for (final y in _linspace(minY, maxY, 8)) {
      for (final x in _linspace(minX, maxX, 8)) {
        final derivatives = _derivatives(_Point(x, y), center, span);
        final derivative = _dot(
          axis == 0 ? derivatives.$1 : derivatives.$2,
          coefficients,
        );
        if (derivative < .5 / spacing || derivative > 1.6 / spacing) {
          valid = false;
          break;
        }
      }
      if (!valid) break;
    }
    if (!valid) continue;
    final residual = [
      for (var i = 0; i < points.length; i++)
        if (train[i])
          _assign(_dot(features[i], coefficients), 0, 1, ratio, axis + 2).error,
    ];
    final score = _mean(residual.map((e) => math.min(e * e, .25))),
        accepted =
            residual.where((e) => e.abs() <= tolerance).length /
            residual.length;
    if (accepted > bestAccepted ||
        (accepted == bestAccepted && score < bestScore)) {
      bestAccepted = accepted;
      bestScore = score;
      bestCoefficients = coefficients;
      bestRatio = ratio;
    }
    if (accepted > .98) break;
  }
  if (bestCoefficients == null) {
    throw const FormatException(
      'No spatial seed establishes a reliable grid; supply calibration or rectify the page',
    );
  }
  return (bestCoefficients, bestRatio);
}

(_GridFit, _Warp) _fitWarp(
  List<_Point> points,
  double diameter,
  GridConfig cfg,
) {
  if (points.length < 120) {
    throw const FormatException(
      'Curved-page fitting needs at least 120 retained dots; use measured calibration for sparse text',
    );
  }
  final center = _Point(
    _median(points.map((p) => p.x).toList()),
    _median(points.map((p) => p.y).toList()),
  );
  final minX = points.map((p) => p.x).reduce(math.min),
      maxX = points.map((p) => p.x).reduce(math.max);
  final minY = points.map((p) => p.y).reduce(math.min),
      maxY = points.map((p) => p.y).reduce(math.max);
  final span = _Point(maxX - minX, maxY - minY);
  if (math.min(span.x, span.y) < 8 * diameter) {
    throw const FormatException(
      'Insufficient page coverage for curved-page fitting',
    );
  }
  final steps = _localSpacings(points, diameter);
  final order = List.generate(points.length, (i) => i)
    ..sort((a, b) {
      final x = points[a].x.compareTo(points[b].x);
      return x != 0 ? x : points[a].y.compareTo(points[b].y);
    });
  final train = List.filled(points.length, true);
  for (var i = 0; i < order.length; i += 5) {
    train[order[i]] = false;
  }
  final x = _warpAxis(
    points,
    0,
    diameter,
    steps.x,
    center,
    span,
    train,
    cfg.cellPitchBounds,
    cfg.tolerance,
  );
  final y = _warpAxis(
    points,
    1,
    diameter,
    steps.y,
    center,
    span,
    train,
    cfg.linePitchBounds,
    cfg.tolerance,
  );
  final coefficients = [
        for (var i = 0; i < 15; i++) [x.$1[i], y.$1[i]],
      ],
      ratios = _Point(x.$2, y.$2);
  final provisional = _Warp(
    center,
    span,
    coefficients,
    ratios,
    steps,
    0,
    train.where((v) => !v).length,
  );
  final latent = points.map(provisional.forward).toList();
  final ax = latent.map((p) => _assign(p.x, 0, 1, ratios.x, 2)).toList(),
      ay = latent.map((p) => _assign(p.y, 0, 1, ratios.y, 3)).toList();
  var fit = _GridFit(
    ax.map((a) => a.index).toList(),
    ax.map((a) => a.slot).toList(),
    ay.map((a) => a.index).toList(),
    ay.map((a) => a.slot).toList(),
    ax.map((a) => a.error).toList(),
    ay.map((a) => a.error).toList(),
    List.generate(
      points.length,
      (i) =>
          ax[i].error.abs() <= cfg.tolerance &&
          ay[i].error.abs() <= cfg.tolerance,
    ),
  );
  var heldOut = _fraction([
    for (var i = 0; i < train.length; i++)
      if (!train[i]) fit.good[i],
  ]);
  for (final y in _linspace(minY, maxY, 12)) {
    for (final x in _linspace(minX, maxX, 12)) {
      final (jx, jy) = provisional.jacobian(_Point(x, y));
      if (jx.x * jy.y - jy.x * jx.y <= 0 ||
          jx.x < .5 / steps.x ||
          jx.x > 1.6 / steps.x ||
          jy.y < .5 / steps.y ||
          jy.y > 1.6 / steps.y) {
        throw const FormatException(
          'Curved-page fit would fold or distort the grid excessively',
        );
      }
    }
  }
  _LocalFit? local;
  Map<String, dynamic>? quality;
  if (cfg.refineLines || cfg.refineSegments) {
    try {
      final candidate = _refineLines(
        points,
        fit,
        train,
        ratios,
        steps,
        cfg.tolerance,
        (q, row, line) => provisional.inverse(_Point(q, line * ratios.y + row)),
        refineSegments: cfg.refineSegments,
      );
      if (candidate != null) {
        final before = candidate.coarseResidual
            .map((p) => math.min(p.squared, .5))
            .toList();
        final after = List.generate(
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
        final accepted = _fraction(candidate.fit.good),
            previous = _fraction(fit.good);
        quality = {
          'accepted_fraction': accepted,
          'held_out_accepted_fraction': candidate.heldOut,
          'old_residual_loss': _mean(before),
          'new_residual_loss': _mean(after),
          'old_validation_loss': loss(before, false),
          'new_validation_loss': loss(after, false),
        };
        final improved =
            accepted > previous + .003 ||
            (accepted >= previous - .005 &&
                loss(after, true) < loss(before, true) &&
                loss(after, false) <= loss(before, false) + 1e-5);
        if (improved && candidate.heldOut >= heldOut - .005) {
          local = candidate;
          fit = candidate.fit;
          heldOut = candidate.heldOut;
        }
      }
    } on FormatException catch (error) {
      quality = {'rejected_reason': error.message};
    }
  }
  if (_fraction(fit.good) < cfg.minAcceptedFraction ||
      heldOut < cfg.minAcceptedFraction) {
    throw FormatException(
      'Curved-page grid remains unreliable (all dots ${(_fraction(fit.good) * 100).toStringAsFixed(1)}%, held-out ${(heldOut * 100).toStringAsFixed(1)}%)',
    );
  }
  final warp = _Warp(
    center,
    span,
    coefficients,
    ratios,
    steps,
    heldOut,
    train.where((v) => !v).length,
  )..localQuality = quality;
  if (local != null) {
    warp.lineModels = local.models;
    warp.locallyReassigned = local.changed;
  }
  return (fit, warp);
}
