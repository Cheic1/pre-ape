/// Wire DTO della geometria estratta dalla planimetria (`FloorPlan`,
/// `POST/GET /api/v1/documents/{id}/cad`). Coordinate in metri, origine in
/// basso a sinistra, y verso l'alto.
library;

import 'dart:ui' show Offset;

List<Offset> _points(Object? raw) => (raw as List<dynamic>? ?? const [])
    .whereType<List<dynamic>>()
    .where((p) => p.length >= 2)
    .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
    .toList(growable: false);

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

class PlanPolygon {
  const PlanPolygon({required this.outer, this.holes = const []});

  factory PlanPolygon.fromJson(Map<String, dynamic> json) => PlanPolygon(
        outer: _points(json['outer']),
        holes: (json['holes'] as List<dynamic>? ?? const [])
            .map(_points)
            .toList(growable: false),
      );

  final List<Offset> outer;
  final List<List<Offset>> holes;
}

class PlanRoom {
  const PlanRoom({
    required this.polygon,
    required this.areaM2,
    required this.labelPoint,
    this.label,
  });

  factory PlanRoom.fromJson(Map<String, dynamic> json) {
    final lp = _points([json['label_point']]);
    return PlanRoom(
      polygon: _points(json['polygon']),
      areaM2: _d(json['area_m2']),
      labelPoint: lp.isEmpty ? Offset.zero : lp.first,
      label: json['label'] as String?,
    );
  }

  final List<Offset> polygon;
  final double areaM2;
  final Offset labelPoint;
  final String? label;
}

class PlanOpening {
  const PlanOpening({
    required this.kind,
    required this.polygon,
    required this.widthM,
    required this.exterior,
  });

  factory PlanOpening.fromJson(Map<String, dynamic> json) => PlanOpening(
        kind: json['kind'] as String? ?? 'porta',
        polygon: _points(json['polygon']),
        widthM: _d(json['width_m']),
        exterior: json['exterior'] as bool? ?? false,
      );

  /// `porta` | `finestra`.
  final String kind;
  final List<Offset> polygon;
  final double widthM;
  final bool exterior;

  bool get isWindow => kind == 'finestra';
}

class PlanStats {
  const PlanStats({
    required this.grossAreaM2,
    required this.netAreaM2,
    required this.perimeterM,
    required this.rooms,
    required this.doors,
    required this.windows,
    required this.windowsWidthM,
  });

  factory PlanStats.fromJson(Map<String, dynamic> json) => PlanStats(
        grossAreaM2: _d(json['gross_area_m2']),
        netAreaM2: _d(json['net_area_m2']),
        perimeterM: _d(json['perimeter_m']),
        rooms: (json['rooms'] as num?)?.toInt() ?? 0,
        doors: (json['doors'] as num?)?.toInt() ?? 0,
        windows: (json['windows'] as num?)?.toInt() ?? 0,
        windowsWidthM: _d(json['windows_width_m']),
      );

  final double grossAreaM2;
  final double netAreaM2;
  final double perimeterM;
  final int rooms;
  final int doors;
  final int windows;
  final double windowsWidthM;
}

class FloorPlan {
  const FloorPlan({
    required this.scaleDenominator,
    required this.metersPerPx,
    required this.wallHeightM,
    required this.walls,
    required this.footprint,
    required this.rooms,
    required this.openings,
    required this.stats,
    this.warnings = const [],
  });

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        (json[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(f)
            .toList(growable: false);
    return FloorPlan(
      scaleDenominator: (json['scale_denominator'] as num?)?.toInt(),
      metersPerPx: _d(json['meters_per_px']),
      wallHeightM: _d(json['wall_height_m']),
      walls: list('walls', PlanPolygon.fromJson),
      footprint: list('footprint', PlanPolygon.fromJson),
      rooms: list('rooms', PlanRoom.fromJson),
      openings: list('openings', PlanOpening.fromJson),
      stats: PlanStats.fromJson(
          json['stats'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((w) => w.toString())
          .toList(growable: false),
    );
  }

  /// null quando la scala è stata calibrata direttamente (metri/pixel).
  final int? scaleDenominator;
  final double metersPerPx;
  final double wallHeightM;
  final List<PlanPolygon> walls;
  final List<PlanPolygon> footprint;
  final List<PlanRoom> rooms;
  final List<PlanOpening> openings;
  final PlanStats stats;
  final List<String> warnings;
}
