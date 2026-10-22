part of 'grouping.dart';

class _Point {
  const _Point(this.x, this.y);
  final double x, y;
  double operator [](int axis) => axis == 0 ? x : y;
  _Point operator +(_Point p) => _Point(x + p.x, y + p.y);
  _Point operator -(_Point p) => _Point(x - p.x, y - p.y);
  _Point operator *(double scale) => _Point(x * scale, y * scale);
  double get squared => x * x + y * y;
  List<double> get list => [x, y];
}

double _median(List<double> values) => _percentile(values, .5);
double _percentile(List<double> values, double fraction) {
  if (values.isEmpty) throw const FormatException('Insufficient grid evidence');
  final sorted = [...values]..sort();
  final position = (sorted.length - 1) * fraction;
  return sorted[position.floor()] +
      (sorted[position.ceil()] - sorted[position.floor()]) *
          (position - position.floor());
}

double _mean(Iterable<double> values) {
  var sum = 0.0, count = 0;
  for (final v in values) {
    sum += v;
    count++;
  }
  return count == 0 ? double.nan : sum / count;
}

double _fraction(List<bool> values) =>
    values.where((v) => v).length / values.length;
double _dot(List<double> a, List<double> b) {
  var value = 0.0;
  for (var i = 0; i < a.length; i++) {
    value += a[i] * b[i];
  }
  return value;
}

List<double> _linspace(double lo, double hi, int n) => [
  for (var i = 0; i < n; i++) lo + (hi - lo) * i / (n - 1),
];
int _rint(double x) {
  final lower = x.floor();
  return x - lower == .5 ? (lower.isEven ? lower : lower + 1) : x.round();
}

/// Householder QR with column pivoting, avoiding squared condition numbers.
/// Returns null for rank-deficient systems, as upstream's rank guards require.
List<List<double>>? _lstsq(
  List<List<double>> rows,
  List<List<double>> targets,
) {
  if (rows.isEmpty || rows.length != targets.length) return null;
  final m = rows.length, n = rows.first.length, k = targets.first.length;
  if (m < n || n == 0) return null;
  final a = rows.map((r) => [...r]).toList(),
      b = targets.map((r) => [...r]).toList();
  final permutation = List.generate(n, (i) => i);
  var initialNorm = 0.0;
  for (var col = 0; col < n; col++) {
    var best = col, largest = -1.0;
    for (var candidate = col; candidate < n; candidate++) {
      var norm = 0.0;
      for (var r = col; r < m; r++) {
        norm += a[r][candidate] * a[r][candidate];
      }
      if (norm > largest) {
        best = candidate;
        largest = norm;
      }
    }
    if (col == 0) initialNorm = math.sqrt(largest);
    if (math.sqrt(math.max(0, largest)) <= math.max(1, initialNorm) * 1e-12) {
      return null;
    }
    if (best != col) {
      for (final row in a) {
        final temp = row[col];
        row[col] = row[best];
        row[best] = temp;
      }
      final temp = permutation[col];
      permutation[col] = permutation[best];
      permutation[best] = temp;
    }
    final norm = math.sqrt(largest);
    final alpha = a[col][col] >= 0 ? -norm : norm;
    final v = [for (var r = col; r < m; r++) a[r][col]];
    v[0] -= alpha;
    final denominator = _dot(v, v);
    for (var c = col; c < n; c++) {
      var projection = 0.0;
      for (var r = col; r < m; r++) {
        projection += v[r - col] * a[r][c];
      }
      projection *= 2 / denominator;
      for (var r = col; r < m; r++) {
        a[r][c] -= projection * v[r - col];
      }
    }
    for (var c = 0; c < k; c++) {
      var projection = 0.0;
      for (var r = col; r < m; r++) {
        projection += v[r - col] * b[r][c];
      }
      projection *= 2 / denominator;
      for (var r = col; r < m; r++) {
        b[r][c] -= projection * v[r - col];
      }
    }
  }
  final solution = List.generate(n, (_) => List.filled(k, 0.0));
  for (var c = 0; c < k; c++) {
    final x = List.filled(n, 0.0);
    for (var r = n - 1; r >= 0; r--) {
      var value = b[r][c];
      for (var j = r + 1; j < n; j++) {
        value -= a[r][j] * x[j];
      }
      x[r] = value / a[r][r];
    }
    for (var r = 0; r < n; r++) {
      solution[permutation[r]][c] = x[r];
    }
  }
  return solution;
}

class _KdNode {
  const _KdNode(this.index, this.axis, this.left, this.right);
  final int index, axis;
  final _KdNode? left, right;
}

class _KdTree {
  _KdTree(this.points) {
    root = _build(List.generate(points.length, (i) => i), 0);
  }
  final List<_Point> points;
  late final _KdNode? root;
  _KdNode? _build(List<int> indices, int depth) {
    if (indices.isEmpty) return null;
    final axis = depth % 2;
    indices.sort((a, b) {
      final c = points[a][axis].compareTo(points[b][axis]);
      return c == 0 ? a.compareTo(b) : c;
    });
    final mid = indices.length ~/ 2;
    return _KdNode(
      indices[mid],
      axis,
      _build(indices.sublist(0, mid), depth + 1),
      _build(indices.sublist(mid + 1), depth + 1),
    );
  }

  List<int> nearest(_Point p, int count) {
    final best = <(double, int)>[];
    void visit(_KdNode? node) {
      if (node == null) return;
      final delta = p[node.axis] - points[node.index][node.axis];
      visit(delta <= 0 ? node.left : node.right);
      final distance = (p - points[node.index]).squared;
      best.add((distance, node.index));
      best.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c == 0 ? a.$2.compareTo(b.$2) : c;
      });
      if (best.length > count) best.removeLast();
      if (best.length < count || delta * delta <= best.last.$1) {
        visit(delta <= 0 ? node.right : node.left);
      }
    }

    visit(root);
    return best.map((v) => v.$2).toList();
  }

  List<int> within(_Point p, double radius) {
    final found = <int>[];
    void visit(_KdNode? node) {
      if (node == null) return;
      if ((p - points[node.index]).squared <= radius * radius) {
        found.add(node.index);
      }
      final delta = p[node.axis] - points[node.index][node.axis];
      if (delta <= radius) visit(node.left);
      if (delta >= -radius) visit(node.right);
    }

    visit(root);
    return found;
  }
}

typedef _Assignment = ({int index, int slot, double error});
_Assignment _assign(
  double value,
  double origin,
  double spacing,
  double pitch,
  int slots,
) {
  var best = (index: 0, slot: 0, error: double.infinity);
  for (var slot = 0; slot < slots; slot++) {
    final index = _rint((value - origin - slot * spacing) / pitch);
    final error = value - (origin + index * pitch + slot * spacing);
    if (error.abs() < best.error.abs()) {
      best = (index: index, slot: slot, error: error);
    }
  }
  return best;
}

class _Axis {
  const _Axis(this.origin, this.gap, this.pitch, this.score);
  final double origin, gap, pitch, score;
  _Assignment assign(double value, int slots) =>
      _assign(value, origin, gap, pitch, slots);
}

List<double> _clusters(List<double> values, double tolerance) {
  final sorted = [...values]..sort(), groups = <List<double>>[];
  var sum = 0.0;
  for (final v in sorted) {
    if (groups.isEmpty || v - sum / groups.last.length > tolerance) {
      groups.add([v]);
      sum = v;
    } else {
      groups.last.add(v);
      sum += v;
    }
  }
  return groups.map(_median).toList();
}

_Axis _fitAxis(
  List<double> values,
  int slots,
  double diameter, {
  double? spacing,
  double? pitch,
  double? origin,
  (double, double)? pitchBounds,
  double maxSpacingToDiameter = 2.5,
  bool refineSpacing = false,
}) {
  final spacingGiven = spacing != null && !refineSpacing;
  final levels = _clusters(values, diameter * .45);
  final gaps = [
    for (var i = 1; i < levels.length; i++) levels[i] - levels[i - 1],
  ];
  if (spacing == null) {
    if (gaps.length < slots - 1) {
      throw const FormatException(
        'Too little grid evidence; supply measured calibration',
      );
    }
    spacing = _percentile(gaps, .2);
    if (spacing > diameter * maxSpacingToDiameter) {
      throw const FormatException('Cannot establish within-cell dot spacing');
    }
  }
  if (!spacing.isFinite ||
      spacing <= 0 ||
      (pitch != null && (!pitch.isFinite || pitch <= (slots - 1) * spacing)) ||
      (origin != null && !origin.isFinite)) {
    throw const FormatException('Invalid grid calibration');
  }
  final baseSpacing = spacing;
  final bounds = pitchBounds ?? (slots == 2 ? (2.05, 3.5) : (3.5, 5.5));
  double loss(
    double o,
    double d,
    double p,
    List<double> sample, {
    bool clip = true,
  }) => _mean(
    sample.map((v) {
      final e = _assign(v, o, d, p, slots).error / d;
      return clip ? math.min(e * e, .25) : e * e;
    }),
  );
  if (pitch == null && levels.length == slots) {
    final step = spacingGiven ? spacing : _median(gaps);
    if (gaps.every((g) => (g - step).abs() <= .15 * step)) {
      final start = origin ?? levels.first;
      final period =
          step * (slots == 2 ? 2.4 : 4.0).clamp(bounds.$1, bounds.$2);
      return _Axis(
        start,
        step,
        period,
        loss(start, step, period, values, clip: false),
      );
    }
  }
  final pitches = <double>[];
  if (pitch != null) {
    pitches.add(pitch);
  } else {
    final bins = <int, List<double>>{};
    for (var step = 1; step < math.min(7, levels.length); step++) {
      for (var i = step; i < levels.length; i++) {
        final d = levels[i] - levels[i - step];
        if (d > bounds.$1 * spacing && d < bounds.$2 * spacing) {
          bins.putIfAbsent(_rint(d / (spacing * .04)), () => []).add(d);
        }
      }
    }
    if (bins.isEmpty) {
      throw const FormatException(
        'Cannot infer grid pitch; supply calibration',
      );
    }
    final keys = bins.keys.toList()
      ..sort((a, b) {
        final count = bins[b]!.length.compareTo(bins[a]!.length);
        return count != 0 ? count : a.compareTo(b);
      });
    pitches.addAll(keys.take(14).map((k) => _median(bins[k]!)));
  }
  final sample = levels.length <= 160
      ? levels
      : [
          for (var i = 0; i < 160; i++)
            levels[(i * (levels.length - 1) / 159).floor()],
        ];
  final trials = <_Axis>[];
  for (final period in pitches) {
    final origins = origin != null
        ? [origin]
        : [
            for (final v in levels.take(24))
              for (var s = 0; s < slots; s++) v - s * spacing,
          ];
    for (final start in origins) {
      trials.add(
        _Axis(start, spacing, period, loss(start, spacing, period, sample)),
      );
    }
  }
  trials.sort((a, b) {
    for (final pair in [
      (a.score, b.score),
      (a.origin, b.origin),
      (a.gap, b.gap),
      (a.pitch, b.pitch),
    ]) {
      final c = pair.$1.compareTo(pair.$2);
      if (c != 0) return c;
    }
    return 0;
  });
  _Axis? best;
  for (final trial in trials.take(16)) {
    var o = trial.origin, d = trial.gap, p = trial.pitch;
    for (var iteration = 0; iteration < 8; iteration++) {
      final rows = <List<double>>[], target = <List<double>>[];
      final free = [origin == null, !spacingGiven, pitch == null];
      final known = [o, d, p];
      for (final value in sample) {
        final a = _assign(value, o, d, p, slots);
        if (a.error.abs() >= d * .4) continue;
        final full = [1.0, a.slot.toDouble(), a.index.toDouble()];
        var fixed = 0.0;
        for (var c = 0; c < 3; c++) {
          if (!free[c]) fixed += full[c] * known[c];
        }
        rows.add([
          for (var c = 0; c < 3; c++)
            if (free[c]) full[c],
        ]);
        target.add([value - fixed]);
      }
      if (rows.length < 4 || !free.contains(true)) break;
      final fit = _lstsq(rows, target);
      if (fit == null) break;
      var j = 0;
      final next = [
        for (var c = 0; c < 3; c++) free[c] ? fit[j++][0] : known[c],
      ];
      if (next[1] <= 0 ||
          next[2] <= (slots - 1) * next[1] ||
          (next[1] / baseSpacing - 1).abs() > .35 ||
          (pitch == null &&
              (next[2] / next[1] < bounds.$1 ||
                  next[2] / next[1] > bounds.$2))) {
        break;
      }
      o = next[0];
      d = next[1];
      p = next[2];
    }
    final candidate = _Axis(o, d, p, loss(o, d, p, sample));
    if (best == null || candidate.score < best.score) best = candidate;
  }
  if (origin == null &&
      sample.map((v) => best!.assign(v, slots).slot).toSet().length < slots) {
    throw const FormatException(
      'Missing complete row/column evidence; supply calibration',
    );
  }
  return best!;
}
