import 'dart:math' as math;

import '../../models/telemetry.dart';
import '../constants/app_config.dart';
import '../utils/clamp.dart';

double _toRadians(double degrees) => degrees * math.pi / 180;

double _toDegrees(double radians) => radians * 180 / math.pi;

/// A run of bearings the rover could travel through.
///
/// Bearings use the servo's own frame throughout: 0° is hard left, 90° is dead
/// ahead, 180° is hard right — the same convention the radar draws in.
class TraversableGap {
  const TraversableGap({
    required this.startDegrees,
    required this.endDegrees,
    required this.headingDegrees,
    required this.clearanceCm,
    required this.isFullyObserved,
  });

  final int startDegrees;
  final int endDegrees;

  /// The bearing to actually steer. For a narrow gap this is the middle; for a
  /// wide one it sits just inside the edge nearest the target heading, so the
  /// rover commits to the opening instead of drifting to the centre of a room.
  final int headingDegrees;

  /// How far the gap has been seen to be clear.
  final int clearanceCm;

  /// False when part of the gap rests on bearings the sweep never covered.
  /// An unobserved bearing is assumed passable — which is a guess, and the UI
  /// says so rather than drawing it like a measurement.
  final bool isFullyObserved;

  int get widthDegrees => endDegrees - startDegrees;

  /// Signed offset from a reference bearing; negative is left of it.
  int offsetFrom(int reference) => headingDegrees - reference;

  /// `40° LEFT`, `DEAD AHEAD`, `15° RIGHT`.
  String describeRelativeTo(int reference) {
    final offset = offsetFrom(reference);
    if (offset == 0) return 'DEAD AHEAD';
    return '${offset.abs()}° ${offset < 0 ? "LEFT" : "RIGHT"}';
  }

  @override
  String toString() =>
      'TraversableGap($startDegrees–$endDegrees°, steer $headingDegrees°, '
      'clear ${clearanceCm}cm)';
}

/// What a cluster of returns looks like it is.
enum SurfaceKind {
  wall('WALL', 'A flat run of returns'),
  corner('CORNER', 'Two flat runs meeting at an angle'),
  object('OBJECT', 'A compact return'),
  opening('OPENING', 'Wide enough to drive through'),
  unclear('UNCLEAR', 'Returns that do not resolve into a shape');

  const SurfaceKind(this.label, this.description);

  final String label;
  final String description;

  bool get isObstacle => this != opening;
}

/// One classified feature of the space ahead.
class RadarSurface {
  const RadarSurface({
    required this.kind,
    required this.startDegrees,
    required this.endDegrees,
    required this.nearestCm,
    required this.pointCount,
    required this.deviationCm,
  });

  final SurfaceKind kind;
  final int startDegrees;
  final int endDegrees;

  /// Closest point on the surface, or the observed clearance of an opening.
  final int nearestCm;

  final int pointCount;

  /// Largest perpendicular departure from a straight line, in cm. Zero for
  /// anything with fewer than three points, where straightness is not a
  /// question the geometry can answer.
  final double deviationCm;

  int get spanDegrees => endDegrees - startDegrees;

  int get bearingDegrees => (startDegrees + endDegrees) ~/ 2;

  String get label => spanDegrees == 0
      ? '${kind.label} $bearingDegrees°'
      : '${kind.label} $startDegrees–$endDegrees°';

  @override
  String toString() => '$label (${nearestCm}cm)';
}

/// The app's reading of the space in front of the rover.
class FieldAnalysis {
  const FieldAnalysis({
    required this.gaps,
    required this.recommended,
    required this.surfaces,
    required this.nearestCm,
    required this.observedDegrees,
    required this.blockedFraction,
    required this.referenceBearing,
  });

  static const FieldAnalysis empty = FieldAnalysis(
    gaps: <TraversableGap>[],
    recommended: null,
    surfaces: <RadarSurface>[],
    nearestCm: null,
    observedDegrees: 0,
    blockedFraction: 0,
    referenceBearing: 90,
  );

  /// Every gap wide enough for the chassis, left to right.
  final List<TraversableGap> gaps;

  /// The one worth steering for, or `null` when nothing is passable.
  final TraversableGap? recommended;

  /// Obstacles and openings together, in bearing order.
  final List<RadarSurface> surfaces;

  final int? nearestCm;

  /// How much of the 180° sweep the sensor actually covered.
  final int observedDegrees;

  /// Fraction of the sweep the chassis could not fit through.
  final double blockedFraction;

  /// The bearing gaps are measured against — dead ahead, from settings.
  final int referenceBearing;

  bool get hasData => observedDegrees > 0;

  bool get isBlocked => hasData && recommended == null;

  List<RadarSurface> get obstacles =>
      surfaces.where((s) => s.kind.isObstacle).toList(growable: false);

  /// One line for the driver.
  String get summary {
    if (!hasData) return 'No sweep data yet';
    final gap = recommended;
    if (gap == null) return 'No route wide enough for the chassis';
    return 'Gap ${gap.describeRelativeTo(referenceBearing)} · '
        '${gap.widthDegrees}° wide';
  }
}

/// Turns a servo sweep into gaps and surfaces.
///
/// Two independent readings of the same samples:
///
/// * **Free space**, via a Vector Field Histogram. Every return is enlarged by
///   the chassis half-width and the beam cone, the remaining bearings are
///   grouped into valleys, and the valley worth steering for is picked the way
///   VFH picks it — nearest the target heading, biased toward width.
/// * **Occupied space**, via iterative end-point fit. Returns are projected
///   into Cartesian coordinates and split at their largest departure from a
///   straight line until every run is flat, which separates walls from corners
///   from isolated objects.
///
/// Nothing here commands the vehicle. The ESP32 runs its own avoidance from its
/// own readings; this is what the *app* can say about the same sweep, drawn on
/// the radar so the driver can see what the rover is about to deal with.
abstract final class RadarField {
  static FieldAnalysis analyse({
    required Map<int, RadarSample> samples,
    required int clearanceCm,
    int roverWidthCm = AppConfig.roverWidthCm,
    int referenceBearing = 90,
    Duration sampleTtl = AppConfig.perceptionSampleTtl,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final fresh = _fresh(samples, at, sampleTtl);
    if (fresh.isEmpty) return FieldAnalysis.empty;

    const step = AppConfig.perceptionSectorDegrees;
    const sectorCount = 180 ~/ step + 1;

    final observed = List<bool>.filled(sectorCount, false);
    final blocked = List<bool>.filled(sectorCount, false);
    final returns = <_Return>[];
    final blocking = <_Return>[];

    final halfWidth = roverWidthCm / 2;

    for (final sample in fresh) {
      // The cone means one ping is evidence about a spread of bearings, so a
      // sweep of five angles still covers most of the arc.
      _mark(observed, sample.angle, AppConfig.sensorBeamHalfWidthDegrees);

      final distance = _usable(sample.distanceCm);
      if (distance == null) continue;

      final entry = _Return(sample.angle, distance.toDouble());
      returns.add(entry);
      if (distance >= clearanceCm) continue;

      blocking.add(entry);

      // Enlargement: how far either side of the return the chassis would
      // still clip it. At or inside the half-width this saturates at 90° —
      // something touching the wheel blocks every bearing.
      final ratio = clampDouble(
        halfWidth / math.max(distance.toDouble(), halfWidth),
        0,
        1,
      );
      final spread =
          _toDegrees(math.asin(ratio)) + AppConfig.sensorBeamHalfWidthDegrees;
      _mark(blocked, sample.angle, spread);
    }

    final observedDegrees = observed.where((o) => o).length * step;
    if (observedDegrees == 0) return FieldAnalysis.empty;

    final blockedCount = blocked.where((b) => b).length;
    final gaps = _gaps(
      blocked: blocked,
      observed: observed,
      returns: returns,
      blocking: blocking,
      halfWidth: halfWidth,
      clearanceCm: clearanceCm,
      referenceBearing: referenceBearing,
    );

    final surfaces = <RadarSurface>[
      ..._surfaces(returns),
      for (final gap in gaps)
        RadarSurface(
          kind: SurfaceKind.opening,
          startDegrees: gap.startDegrees,
          endDegrees: gap.endDegrees,
          nearestCm: gap.clearanceCm,
          pointCount: 0,
          deviationCm: 0,
        ),
    ]..sort((a, b) => a.startDegrees.compareTo(b.startDegrees));

    return FieldAnalysis(
      gaps: List.unmodifiable(gaps),
      recommended: _pick(gaps, referenceBearing),
      surfaces: List.unmodifiable(surfaces),
      nearestCm: returns.isEmpty
          ? null
          : returns
                .map((r) => r.distanceCm)
                .reduce((a, b) => math.min(a, b))
                .round(),
      observedDegrees: observedDegrees,
      blockedFraction: blockedCount / sectorCount,
      referenceBearing: referenceBearing,
    );
  }

  // --- Free space ----------------------------------------------------------

  static List<TraversableGap> _gaps({
    required List<bool> blocked,
    required List<bool> observed,
    required List<_Return> returns,
    required List<_Return> blocking,
    required double halfWidth,
    required int clearanceCm,
    required int referenceBearing,
  }) {
    const step = AppConfig.perceptionSectorDegrees;
    final gaps = <TraversableGap>[];

    var index = 0;
    while (index < blocked.length) {
      if (blocked[index]) {
        index++;
        continue;
      }

      final start = index;
      while (index < blocked.length && !blocked[index]) {
        index++;
      }
      final end = index - 1;

      final startDegrees = start * step;
      final endDegrees = end * step;

      // What the rover would have to squeeze past to use this gap sets how
      // wide the gap has to be: the same 20° opening is passable at 2m and
      // impassable at 30cm.
      final bounding = _boundingDistance(startDegrees, endDegrees, blocking);
      final reference = bounding ?? clearanceCm.toDouble();
      final required = math.max(
        AppConfig.perceptionMinGapDegrees.toDouble(),
        2 *
            _toDegrees(
              math.asin(
                clampDouble(halfWidth / math.max(reference, halfWidth), 0, 1),
              ),
            ),
      );

      if (endDegrees - startDegrees < required) continue;

      final inside = returns.where(
        (r) => r.angleDegrees >= startDegrees && r.angleDegrees <= endDegrees,
      );
      final clearance = inside.isEmpty
          ? AppConfig.sensorMaxRangeCm
          : inside
                .map((r) => r.distanceCm)
                .reduce((a, b) => math.min(a, b))
                .round();

      var fullyObserved = true;
      for (var i = start; i <= end; i++) {
        if (!observed[i]) {
          fullyObserved = false;
          break;
        }
      }

      gaps.add(
        TraversableGap(
          startDegrees: startDegrees,
          endDegrees: endDegrees,
          headingDegrees: _heading(startDegrees, endDegrees, referenceBearing),
          clearanceCm: clearance,
          isFullyObserved: fullyObserved,
        ),
      );
    }

    return gaps;
  }

  /// Nearest blocking return on either flank of a gap.
  static double? _boundingDistance(
    int startDegrees,
    int endDegrees,
    List<_Return> blocking,
  ) {
    _Return? left;
    _Return? right;
    for (final entry in blocking) {
      if (entry.angleDegrees < startDegrees) {
        if (left == null || entry.angleDegrees > left.angleDegrees) {
          left = entry;
        }
      } else if (entry.angleDegrees > endDegrees) {
        if (right == null || entry.angleDegrees < right.angleDegrees) {
          right = entry;
        }
      }
    }
    if (left == null && right == null) return null;
    if (left == null) return right!.distanceCm;
    if (right == null) return left.distanceCm;
    return math.min(left.distanceCm, right.distanceCm);
  }

  /// VFH's steering choice: the middle of a narrow valley, or a committed line
  /// just inside the near edge of a wide one.
  static int _heading(int startDegrees, int endDegrees, int target) {
    const wide = AppConfig.perceptionWideGapDegrees;
    final width = endDegrees - startDegrees;
    if (width <= wide) return (startDegrees + endDegrees) ~/ 2;

    final margin = wide ~/ 2;
    final low = startDegrees + margin;
    final high = endDegrees - margin;
    if (target >= low && target <= high) return target;
    return (target - startDegrees).abs() <= (target - endDegrees).abs()
        ? low
        : high;
  }

  /// Deviation from dead ahead, discounted by width. A gap has to be
  /// meaningfully wider to be worth a detour, and a hair-wide slot straight
  /// ahead should not beat a comfortable opening just off it.
  static TraversableGap? _pick(List<TraversableGap> gaps, int target) {
    TraversableGap? best;
    var bestCost = double.infinity;
    for (final gap in gaps) {
      final cost =
          (gap.headingDegrees - target).abs() -
          gap.widthDegrees * AppConfig.perceptionGapWidthWeight;
      if (cost < bestCost) {
        bestCost = cost;
        best = gap;
      }
    }
    return best;
  }

  // --- Occupied space ------------------------------------------------------

  static List<RadarSurface> _surfaces(List<_Return> returns) {
    if (returns.isEmpty) return const [];

    final points = [...returns]
      ..sort((a, b) => a.angleDegrees.compareTo(b.angleDegrees));

    final meanRange =
        points.map((p) => p.distanceCm).reduce((a, b) => a + b) / points.length;
    final tolerance = math.max(
      AppConfig.perceptionStraightnessCm,
      AppConfig.perceptionStraightnessFraction * meanRange,
    );

    final clusters = <List<_Return>>[];
    for (final cluster in _byDiscontinuity(points)) {
      _split(cluster, 0, cluster.length - 1, tolerance, clusters);
    }

    final segments = clusters
        .map((cluster) => _Segment(cluster, tolerance))
        .toList(growable: false);

    return _mergeCorners(segments);
  }

  /// Splits where neighbouring returns are too far apart to plausibly sit on
  /// the same surface.
  ///
  /// This is the adaptive breakpoint test, and it only works while the sweep is
  /// finer than the worst incidence angle it assumes. The stock five-angle
  /// sweep is 45° apart — nowhere near — so at that resolution the test is
  /// skipped rather than run on assumptions it cannot support. Openings inside
  /// a collinear surface are still found, from the free-space side, by the gap
  /// finder above.
  static List<List<_Return>> _byDiscontinuity(List<_Return> points) {
    if (points.length < 2) return [points];

    final spacings = <int>[];
    for (var i = 1; i < points.length; i++) {
      spacings.add(points[i].angleDegrees - points[i - 1].angleDegrees);
    }
    spacings.sort();
    final median = spacings[spacings.length ~/ 2].toDouble();
    if (median > AppConfig.perceptionFineSweepMaxSpacingDegrees) {
      return [points];
    }

    const lambda = AppConfig.perceptionWorstIncidenceDegrees;
    final clusters = <List<_Return>>[];
    var current = <_Return>[points.first];

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      final spacing = (point.angleDegrees - previous.angleDegrees).toDouble();

      if (spacing >= lambda) {
        clusters.add(current);
        current = <_Return>[point];
        continue;
      }

      final sigma =
          AppConfig.sensorNoiseCm +
          AppConfig.sensorNoiseFraction * previous.distanceCm;
      final limit =
          previous.distanceCm *
              math.sin(_toRadians(spacing)) /
              math.sin(_toRadians(lambda - spacing)) +
          3 * sigma;

      if (_distanceBetween(previous, point) > limit) {
        clusters.add(current);
        current = <_Return>[point];
      } else {
        current.add(point);
      }
    }

    clusters.add(current);
    return clusters;
  }

  /// Iterative end-point fit. Recurses on the point furthest from the line
  /// joining the ends until every run is flat within [tolerance].
  static void _split(
    List<_Return> points,
    int start,
    int end,
    double tolerance,
    List<List<_Return>> out,
  ) {
    if (end - start + 1 <= 2) {
      out.add(points.sublist(start, end + 1));
      return;
    }

    var worst = -1.0;
    var worstIndex = -1;
    for (var i = start + 1; i < end; i++) {
      final deviation = _perpendicular(points[i], points[start], points[end]);
      if (deviation > worst) {
        worst = deviation;
        worstIndex = i;
      }
    }

    if (worstIndex < 0 || worst <= tolerance) {
      out.add(points.sublist(start, end + 1));
      return;
    }

    // The split point belongs to both runs — it is the corner, not a member of
    // one side of it.
    _split(points, start, worstIndex, tolerance, out);
    _split(points, worstIndex, end, tolerance, out);
  }

  /// Two flat runs that meet at an angle are one corner, not two walls.
  static List<RadarSurface> _mergeCorners(List<_Segment> segments) {
    final surfaces = <RadarSurface>[];

    var index = 0;
    while (index < segments.length) {
      final segment = segments[index];
      final next = index + 1 < segments.length ? segments[index + 1] : null;

      if (next != null &&
          segment.kind == SurfaceKind.wall &&
          next.kind == SurfaceKind.wall &&
          _angleBetween(segment, next) >=
              AppConfig.perceptionCornerMinDegrees) {
        surfaces.add(
          RadarSurface(
            kind: SurfaceKind.corner,
            startDegrees: segment.startDegrees,
            endDegrees: next.endDegrees,
            nearestCm: math.min(segment.nearestCm, next.nearestCm),
            pointCount: segment.points.length + next.points.length,
            deviationCm: math.max(segment.deviationCm, next.deviationCm),
          ),
        );
        index += 2;
        continue;
      }

      surfaces.add(
        RadarSurface(
          kind: segment.kind,
          startDegrees: segment.startDegrees,
          endDegrees: segment.endDegrees,
          nearestCm: segment.nearestCm,
          pointCount: segment.points.length,
          deviationCm: segment.deviationCm,
        ),
      );
      index++;
    }

    return surfaces;
  }

  static double _angleBetween(_Segment a, _Segment b) {
    final dot = a.dirX * b.dirX + a.dirY * b.dirY;
    // Lines, not rays: a direction and its opposite describe the same wall, so
    // the answer belongs in 0–90°.
    return _toDegrees(math.acos(clampDouble(dot.abs(), 0, 1)));
  }

  // --- Shared helpers ------------------------------------------------------

  static List<RadarSample> _fresh(
    Map<int, RadarSample> samples,
    DateTime at,
    Duration ttl,
  ) {
    final fresh =
        samples.values
            .where((s) => s.angle >= 0 && s.angle <= 180)
            .where((s) => at.difference(s.takenAt) <= ttl)
            .toList()
          ..sort((a, b) => a.angle.compareTo(b.angle));
    return fresh;
  }

  static int? _usable(int? cm) {
    if (cm == null) return null;
    if (cm < AppConfig.sensorMinRangeCm) return null;
    if (cm > AppConfig.sensorMaxRangeCm) return null;
    return cm;
  }

  static void _mark(List<bool> sectors, int centreDegrees, double spread) {
    const step = AppConfig.perceptionSectorDegrees;
    final low = clampInt(
      ((centreDegrees - spread) / step).floor(),
      0,
      sectors.length - 1,
    );
    final high = clampInt(
      ((centreDegrees + spread) / step).ceil(),
      0,
      sectors.length - 1,
    );
    for (var i = low; i <= high; i++) {
      sectors[i] = true;
    }
  }

  static double _distanceBetween(_Return a, _Return b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _perpendicular(_Return point, _Return a, _Return b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return _distanceBetween(point, a);
    return ((point.x - a.x) * dy - (point.y - a.y) * dx).abs() / length;
  }
}

/// One return, carried in both polar and Cartesian form.
///
/// The Cartesian frame is mirrored relative to the radar drawing (0° maps to
/// +x rather than to the left edge). Nothing downstream cares: clustering, line
/// fitting and angles between lines are all invariant under the reflection, and
/// every value that reaches the UI is a bearing in degrees.
class _Return {
  _Return(this.angleDegrees, this.distanceCm)
    : x = distanceCm * math.cos(_toRadians(angleDegrees.toDouble())),
      y = distanceCm * math.sin(_toRadians(angleDegrees.toDouble()));

  final int angleDegrees;
  final double distanceCm;
  final double x;
  final double y;
}

/// A run of returns after splitting, with the shape it resolved to.
class _Segment {
  _Segment(this.points, double tolerance)
    : assert(points.isNotEmpty, 'a segment needs at least one return'),
      deviationCm = _deviationOf(points),
      _extentCm = _extentOf(points) {
    final first = points.first;
    final last = points.last;
    final dx = last.x - first.x;
    final dy = last.y - first.y;
    final length = math.sqrt(dx * dx + dy * dy);
    dirX = length == 0 ? 1 : dx / length;
    dirY = length == 0 ? 0 : dy / length;

    kind = switch (points.length) {
      1 => SurfaceKind.object,
      2 =>
        _extentCm <= AppConfig.perceptionObjectMaxWidthCm
            ? SurfaceKind.object
            : SurfaceKind.wall,
      _ =>
        deviationCm <= tolerance
            ? SurfaceKind.wall
            : (_extentCm <= AppConfig.perceptionObjectMaxWidthCm
                  ? SurfaceKind.object
                  : SurfaceKind.unclear),
    };
  }

  final List<_Return> points;
  final double deviationCm;
  final double _extentCm;

  late final SurfaceKind kind;
  late final double dirX;
  late final double dirY;

  int get startDegrees => points.first.angleDegrees;
  int get endDegrees => points.last.angleDegrees;
  int get nearestCm =>
      points.map((p) => p.distanceCm).reduce((a, b) => math.min(a, b)).round();

  static double _deviationOf(List<_Return> points) {
    if (points.length < 3) return 0;
    var worst = 0.0;
    for (var i = 1; i < points.length - 1; i++) {
      final deviation = RadarField._perpendicular(
        points[i],
        points.first,
        points.last,
      );
      if (deviation > worst) worst = deviation;
    }
    return worst;
  }

  static double _extentOf(List<_Return> points) =>
      RadarField._distanceBetween(points.first, points.last);
}
