/// Anteprime del disegno estratto dalla planimetria: pianta 2D e modello 3D
/// assonometrico girevole (trascinando), disegnati con `CustomPainter`
/// (nessuna dipendenza 3D: funziona su web, Android e iOS).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pre_ape/models/floor_plan.dart';

const _wallColor = Color(0xFFE6E1D3);
const _wallSide = Color(0xFFB9B2A0);
const _floorColor = Color(0xFF6B6455);
const _doorColor = Color(0xFF22C55E);
const _windowColor = Color(0xFF60A5FA);
const _roomColor = Color(0x2210B981);
const _lineColor = Color(0xFF30363D);

const _doorHeight = 2.10;
const _sill = 0.90;
const _windowTop = 2.20;

/// Bounding box in metri di tutto il disegno.
Rect planBounds(FloorPlan plan) {
  final pts = [
    for (final p in plan.footprint) ...p.outer,
    for (final p in plan.walls) ...p.outer,
  ];
  if (pts.isEmpty) return const Rect.fromLTWH(0, 0, 1, 1);
  var r = Rect.fromPoints(pts.first, pts.first);
  for (final p in pts) {
    r = r.expandToInclude(Rect.fromPoints(p, p));
  }
  return r;
}

String formatM2(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} m²';

// ---------------------------------------------------------------------------
// 2D
// ---------------------------------------------------------------------------
class FloorPlan2DPainter extends CustomPainter {
  FloorPlan2DPainter(this.plan);

  final FloorPlan plan;

  @override
  void paint(Canvas canvas, Size size) {
    final b = planBounds(plan);
    const pad = 16.0;
    final s = math.min((size.width - 2 * pad) / b.width,
        (size.height - 2 * pad) / b.height);
    if (!s.isFinite || s <= 0) return;
    final ox = (size.width - b.width * s) / 2;
    final oy = (size.height - b.height * s) / 2;
    Offset t(Offset p) =>
        Offset(ox + (p.dx - b.left) * s, oy + (b.bottom - p.dy) * s);

    Path ring(List<Offset> pts) =>
        Path()..addPolygon(pts.map(t).toList(), true);

    for (final room in plan.rooms) {
      canvas.drawPath(ring(room.polygon), Paint()..color = _roomColor);
    }
    for (final w in plan.walls) {
      final path = ring(w.outer)..fillType = PathFillType.evenOdd;
      for (final h in w.holes) {
        path.addPolygon(h.map(t).toList(), true);
      }
      canvas.drawPath(path, Paint()..color = _wallColor);
    }
    for (final o in plan.openings) {
      canvas.drawPath(
          ring(o.polygon),
          Paint()
            ..color = o.isWindow ? _windowColor : _doorColor
            ..style = PaintingStyle.fill);
    }
    for (final room in plan.rooms) {
      final tp = TextPainter(
        text: TextSpan(
          text: [if (room.label != null) room.label!, formatM2(room.areaM2)]
              .join('\n'),
          style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 11),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, t(room.labelPoint) - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(FloorPlan2DPainter oldDelegate) => oldDelegate.plan != plan;
}

// ---------------------------------------------------------------------------
// 3D (proiezione ortogonale, algoritmo del pittore)
// ---------------------------------------------------------------------------
class _Prism {
  _Prism(this.outer, this.holes, this.z0, this.z1, this.top, this.side);

  final List<Offset> outer;
  final List<List<Offset>> holes;
  final double z0;
  final double z1;
  final Color top;
  final Color side;
}

double _signedArea(List<Offset> r) {
  var a = 0.0;
  for (var i = 0; i < r.length; i++) {
    final p = r[i], q = r[(i + 1) % r.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

List<_Prism> _prisms(FloorPlan plan) {
  final h = plan.wallHeightM;
  return [
    for (final f in plan.footprint)
      _Prism(f.outer, f.holes, -0.2, 0, _floorColor, _floorColor),
    for (final w in plan.walls) _Prism(w.outer, w.holes, 0, h, _wallColor, _wallSide),
    for (final o in plan.openings)
      if (o.isWindow) ...[
        _Prism(o.polygon, const [], 0, _sill, _wallColor, _wallSide),
        _Prism(o.polygon, const [], math.min(_windowTop, h - 0.05), h,
            _wallColor, _windowColor),
      ] else
        _Prism(o.polygon, const [], math.min(_doorHeight, h - 0.05), h,
            _wallColor, _doorColor),
  ];
}

class FloorPlan3DPainter extends CustomPainter {
  FloorPlan3DPainter(this.plan, {required this.azimuth, required this.elevation})
      : _items = _prisms(plan);

  final FloorPlan plan;

  /// Rotazione attorno all'asse verticale (radianti).
  final double azimuth;

  /// Inclinazione della vista: 0 = di fronte, π/2 = dall'alto.
  final double elevation;
  final List<_Prism> _items;

  @override
  void paint(Canvas canvas, Size size) {
    final b = planBounds(plan);
    final c = b.center;
    final ca = math.cos(azimuth), sa = math.sin(azimuth);
    final ce = math.cos(elevation), se = math.sin(elevation);

    // (x, y, z) metri → (schermo x, schermo y verso l'alto, profondità)
    (double, double, double) project(double x, double y, double z) {
      final rx = (x - c.dx) * ca - (y - c.dy) * sa;
      final ry = (x - c.dx) * sa + (y - c.dy) * ca;
      return (rx, ry * se + z * ce, ry * ce - z * se);
    }

    // scala per far stare tutto nel riquadro
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final corner in [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight]) {
      for (final z in [-0.2, plan.wallHeightM]) {
        final (sx, sy, _) = project(corner.dx, corner.dy, z);
        minX = math.min(minX, sx);
        maxX = math.max(maxX, sx);
        minY = math.min(minY, sy);
        maxY = math.max(maxY, sy);
      }
    }
    const pad = 16.0;
    final s = math.min((size.width - 2 * pad) / (maxX - minX),
        (size.height - 2 * pad) / (maxY - minY));
    if (!s.isFinite || s <= 0) return;
    final ox = size.width / 2 - (minX + maxX) / 2 * s;
    final oy = size.height / 2 + (minY + maxY) / 2 * s;
    Offset screen(double x, double y, double z) {
      final (sx, sy, _) = project(x, y, z);
      return Offset(ox + sx * s, oy - sy * s);
    }

    double depth(double x, double y, double z) => project(x, y, z).$3;

    final faces = <({double depth, Path path, Color color})>[];
    final edge = Paint()
      ..color = _lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (final p in _items) {
      final rings = [p.outer, ...p.holes];
      final outerCcw = _signedArea(p.outer) > 0;
      for (var r = 0; r < rings.length; r++) {
        final ring = rings[r];
        // esterno antiorario / fori orari → normale uscente a destra del lato
        final ccw = _signedArea(ring) > 0;
        final flip = (r == 0) ? !outerCcw : ccw;
        for (var i = 0; i < ring.length; i++) {
          var a = ring[i], q = ring[(i + 1) % ring.length];
          if (flip) (a, q) = (q, a);
          final nx = q.dy - a.dy, ny = -(q.dx - a.dx);
          // normale ruotata: visibile se punta verso l'osservatore (ry < 0)
          final nry = nx * sa + ny * ca;
          if (nry >= 0) continue;
          final path = Path()
            ..addPolygon([
              screen(a.dx, a.dy, p.z0),
              screen(q.dx, q.dy, p.z0),
              screen(q.dx, q.dy, p.z1),
              screen(a.dx, a.dy, p.z1),
            ], true);
          final m = Offset((a.dx + q.dx) / 2, (a.dy + q.dy) / 2);
          final shade = 0.75 + 0.25 * (nx * ca - ny * sa).abs() /
              math.max(1e-9, math.sqrt(nx * nx + ny * ny));
          faces.add((
            depth: depth(m.dx, m.dy, (p.z0 + p.z1) / 2),
            path: path,
            color: Color.lerp(Colors.black, p.side, shade)!,
          ));
        }
      }
      final top = Path()..fillType = PathFillType.evenOdd;
      for (final ring in rings) {
        top.addPolygon([for (final v in ring) screen(v.dx, v.dy, p.z1)], true);
      }
      final cx = p.outer.fold(0.0, (acc, v) => acc + v.dx) / p.outer.length;
      final cy = p.outer.fold(0.0, (acc, v) => acc + v.dy) / p.outer.length;
      faces.add((depth: depth(cx, cy, p.z1) - 0.01, path: top, color: p.top));
    }
    faces.sort((a, b) => b.depth.compareTo(a.depth)); // dal più lontano
    for (final f in faces) {
      canvas.drawPath(f.path, Paint()..color = f.color);
      canvas.drawPath(f.path, edge);
    }
  }

  @override
  bool shouldRepaint(FloorPlan3DPainter oldDelegate) =>
      oldDelegate.plan != plan ||
      oldDelegate.azimuth != azimuth ||
      oldDelegate.elevation != elevation;
}

/// Modello 3D girevole: trascina in orizzontale per ruotare, in verticale per
/// inclinare.
class FloorPlan3DView extends StatefulWidget {
  const FloorPlan3DView({super.key, required this.plan});

  final FloorPlan plan;

  @override
  State<FloorPlan3DView> createState() => _FloorPlan3DViewState();
}

class _FloorPlan3DViewState extends State<FloorPlan3DView> {
  double _azimuth = -math.pi / 6;
  double _elevation = math.pi / 5;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => setState(() {
        _azimuth -= d.delta.dx * 0.01;
        _elevation = (_elevation + d.delta.dy * 0.01).clamp(0.05, math.pi / 2);
      }),
      child: CustomPaint(
        size: Size.infinite,
        painter: FloorPlan3DPainter(widget.plan,
            azimuth: _azimuth, elevation: _elevation),
      ),
    );
  }
}
