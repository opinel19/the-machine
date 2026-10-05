import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../machine/designation.dart';
import '../machine/thing.dart';
import '../theme.dart';

/// Maps upright camera-frame pixels to the screen: the preview fills the view
/// ([BoxFit.cover], centred), may be mirrored, and may be zoomed by the
/// enhance effect (`screen = zoom * mapped + pan`).
class FrameMapping {
  factory FrameMapping(Size frame, Size view, {bool mirror = false, double zoom = 1, Offset pan = Offset.zero}) {
    final scale = math.max(view.width / frame.width, view.height / frame.height);
    return FrameMapping._(
      scale,
      (view.width - frame.width * scale) / 2,
      (view.height - frame.height * scale) / 2,
      mirror ? view.width : null,
      zoom,
      pan,
    );
  }

  const FrameMapping._(this.scale, this.dx, this.dy, this._mirrorWidth, this.zoom, this.pan);

  final double scale;
  final double dx;
  final double dy;
  final double? _mirrorWidth;
  final double zoom;
  final Offset pan;

  Offset point(Offset p) {
    var x = p.dx * scale + dx;
    final mirrorWidth = _mirrorWidth;
    if (mirrorWidth != null) x = mirrorWidth - x;
    return Offset(x * zoom + pan.dx, (p.dy * scale + dy) * zoom + pan.dy);
  }

  Rect rect(Rect r) => Rect.fromPoints(point(r.topLeft), point(r.bottomRight));
}

/// A square around the whole head, like the Machine's boxes, from ML Kit's
/// tighter face rectangle (frame pixels).
Rect headSquare(Rect face) {
  final side = math.max(face.width, face.height) * 1.3;
  return Rect.fromCenter(center: face.center.translate(0, -face.height * 0.06), width: side, height: side);
}

/// Colours of one of the Machine's boxes.
class BoxColors {
  const BoxColors({required this.edges, required this.corners, required this.ticks});

  const BoxColors.all(Color color) : edges = color, corners = color, ticks = color;

  final Color edges;
  final Color corners;
  final Color ticks;

  static BoxColors of(Designation designation) => switch (designation) {
    Designation.analyzing || Designation.irrelevant => const BoxColors.all(MachineColors.irrelevant),
    Designation.verifying || Designation.admin || Designation.asset => const BoxColors.all(MachineColors.admin),
    Designation.relevant || Designation.threat => const BoxColors.all(MachineColors.relevant),
    Designation.catalyst => const BoxColors.all(MachineColors.catalyst),
    // Black box with yellow corners and crosshairs: the analog interface.
    Designation.analogInterface => const BoxColors(
      edges: Colors.black,
      corners: MachineColors.admin,
      ticks: MachineColors.admin,
    ),
    // White box with red corners and crosshairs: an irrelevant threat.
    Designation.perpetrator => const BoxColors(
      edges: MachineColors.irrelevant,
      corners: MachineColors.relevant,
      ticks: MachineColors.relevant,
    ),
    // Our own addition: the subject whose number just came up.
    Designation.personOfInterest => const BoxColors(
      edges: MachineColors.irrelevant,
      corners: MachineColors.irrelevant,
      ticks: MachineColors.admin,
    ),
  };

  /// Colour of the designation tab.
  static Color tabOf(Designation designation) => switch (designation) {
    Designation.relevant || Designation.threat || Designation.perpetrator => MachineColors.relevant,
    Designation.catalyst => MachineColors.catalyst,
    Designation.verifying || Designation.admin || Designation.asset || Designation.analogInterface => MachineColors.admin,
    Designation.personOfInterest => Colors.black,
    Designation.analyzing || Designation.irrelevant => MachineColors.irrelevant,
  };

  static Color inkOn(Color tab) => tab.computeLuminance() > 0.4 ? Colors.black : Colors.white;
}

/// How the Machine drew its boxes in different seasons of the show.
enum BoxSeason {
  /// Season 1: heavy dashes all the way round, chunky corners.
  one('SEASON 1'),

  /// Season 2: lighter, dashes still all the way round.
  two('SEASON 2'),

  /// Seasons 3 to 5: dashes only between the corners, finer brackets.
  later('SEASONS 3-5');

  const BoxSeason(this.label);

  final String label;
}

/// A season's box geometry, in units of 1/1000 of the box side, measured
/// from the show's artwork.
class _BoxSpec {
  const _BoxSpec({
    required this.edge,
    required this.dashOn,
    required this.dashOff,
    required this.dashOffset,
    required this.wholeEdge,
    required this.tickFrom,
    required this.tickTo,
    required this.tickWidth,
    required this.tickShift,
    required this.half,
    required this.arm,
    required this.outerRadius,
    required this.innerRadius,
  });

  final double edge, dashOn, dashOff, dashOffset;

  /// Dashes run the whole edge (under the corners too) rather than only the
  /// stretch between the brackets.
  final bool wholeEdge;
  final double tickFrom, tickTo, tickWidth;

  /// Season 1's ticks sit slightly off the middle.
  final double tickShift;

  /// Corner bracket: half its thickness, how far its arms reach, and its
  /// outer and inner corner radii.
  final double half, arm, outerRadius, innerRadius;

  static const of = {
    BoxSeason.one: _BoxSpec(
      edge: 22, dashOn: 61, dashOff: 44, dashOffset: 8, wholeEdge: true,
      tickFrom: -2, tickTo: 86, tickWidth: 22, tickShift: 7,
      half: 22, arm: 71, outerRadius: 40, innerRadius: 5,
    ),
    BoxSeason.two: _BoxSpec(
      edge: 18, dashOn: 60, dashOff: 45, dashOffset: 55, wholeEdge: true,
      tickFrom: 0, tickTo: 85, tickWidth: 18, tickShift: 0,
      half: 24, arm: 70, outerRadius: 46, innerRadius: 9,
    ),
    BoxSeason.later: _BoxSpec(
      edge: 18, dashOn: 47, dashOff: 47, dashOffset: 47, wholeEdge: false,
      tickFrom: -9, tickTo: 56, tickWidth: 30, tickShift: 0,
      half: 18, arm: 67, outerRadius: 32, innerRadius: 5,
    ),
  };
}

/// The Machine's box: dashed edges, rounded corner brackets and a
/// "crosshair" tick across each edge, in the chosen [season]'s proportions
/// (taken from the show's box artwork).
void paintMachineBox(
  Canvas canvas,
  Rect box,
  BoxColors colors, {
  double opacity = 1,
  bool solidEdges = false,
  BoxSeason season = BoxSeason.later,
}) {
  final spec = _BoxSpec.of[season]!;
  final k = box.shortestSide / 1000;
  final edgeWidth = math.max(spec.edge * k, 1.3);
  final tickWidth = math.max(spec.tickWidth * k, 2.0);

  final edges = Path();
  void edge(Offset from, Offset to) {
    final along = to - from;
    final unit = along / along.distance;
    Offset at(double units) => from + unit * (units * k);
    void dash(double a, double b) => edges
      ..moveTo(at(a).dx, at(a).dy)
      ..lineTo(at(b).dx, at(b).dy);
    if (solidEdges) {
      dash(spec.arm + 5, 1000 - spec.arm - 5);
      return;
    }
    if (spec.wholeEdge) {
      final period = spec.dashOn + spec.dashOff;
      for (var start = -spec.dashOffset; start < 1000; start += period) {
        final a = math.max(start, 0.0), b = math.min(start + spec.dashOn, 1000.0);
        if (b > a) dash(a, b);
      }
      return;
    }
    // Four dashes per half edge, between the bracket and the middle tick.
    for (final start in const [119.0, 213.0, 307.0, 401.0]) {
      dash(start, start + spec.dashOn);
      dash(1000 - start - spec.dashOn, 1000 - start);
    }
  }

  edge(box.topLeft, box.topRight);
  edge(box.topRight, box.bottomRight);
  edge(box.bottomLeft, box.bottomRight);
  edge(box.topLeft, box.bottomLeft);

  // Ticks across each edge, reaching mostly inwards.
  final c = box.center, shift = spec.tickShift * k, from = spec.tickFrom * k, to = spec.tickTo * k;
  final ticks = Path()
    ..moveTo(c.dx + shift, box.top + from)
    ..lineTo(c.dx + shift, box.top + to)
    ..moveTo(c.dx + shift, box.bottom - from)
    ..lineTo(c.dx + shift, box.bottom - to)
    ..moveTo(box.left + from, c.dy + shift)
    ..lineTo(box.left + to, c.dy + shift)
    ..moveTo(box.right - from, c.dy + shift)
    ..lineTo(box.right - to, c.dy + shift);

  // Filled bracket around the top-left corner point; rotated copies make the
  // other three.
  final h = spec.half, a = spec.arm, r = spec.outerRadius, ri = spec.innerRadius;
  final bracket = Path()
    ..moveTo(-h + r, -h)
    ..arcToPoint(Offset(-h, -h + r), radius: Radius.circular(r), clockwise: false)
    ..lineTo(-h, a)
    ..lineTo(h, a)
    ..lineTo(h, h + ri)
    ..arcToPoint(Offset(h + ri, h), radius: Radius.circular(ri))
    ..lineTo(a, h)
    ..lineTo(a, -h)
    ..close();
  final corners = Path();
  for (final (corner, turns) in [
    (box.topLeft, 0),
    (box.topRight, 1),
    (box.bottomRight, 2),
    (box.bottomLeft, 3),
  ]) {
    final m = Matrix4.identity()
      ..translateByDouble(corner.dx, corner.dy, 0, 1)
      ..rotateZ(turns * math.pi / 2)
      ..scaleByDouble(k, k, 1, 1);
    corners.addPath(bracket, Offset.zero, matrix4: m.storage);
  }

  // A faint outline keeps each part legible over any background: dark behind
  // light colours, light behind black.
  Color halo(Color c) => (c.computeLuminance() < 0.1 ? Colors.white : Colors.black).withValues(alpha: 0.35 * opacity);
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;
  canvas
    ..drawPath(edges, stroke
      ..color = halo(colors.edges)
      ..strokeWidth = edgeWidth + 2)
    ..drawPath(ticks, stroke
      ..color = halo(colors.ticks)
      ..strokeWidth = tickWidth + 2)
    ..drawPath(corners, stroke
      ..color = halo(colors.corners)
      ..strokeWidth = 2)
    ..drawPath(edges, stroke
      ..color = colors.edges.withValues(alpha: opacity)
      ..strokeWidth = edgeWidth)
    ..drawPath(ticks, stroke
      ..color = colors.ticks.withValues(alpha: opacity)
      ..strokeWidth = tickWidth)
    ..drawPath(corners, Paint()..color = colors.corners.withValues(alpha: opacity));
}

/// Samaritan's marks for one person.
enum SamaritanMark {
  /// Circles: a tracked individual.
  tracked,

  /// Red upside-down triangle: a target.
  target,

  /// Two triangles, pulsing: a priority target.
  priorityTarget,

  /// Red crosshair: a deviant.
  deviant,

  /// Red circles and crosshair: an enemy combatant.
  enemy;

  static SamaritanMark of(Designation designation) => switch (designation) {
    Designation.admin || Designation.analogInterface => priorityTarget,
    Designation.asset => target,
    Designation.perpetrator => deviant,
    Designation.relevant || Designation.threat => enemy,
    _ => tracked,
  };

  bool get red => this != tracked;
}

/// Circle radius Samaritan draws around a face (frame pixels).
double samaritanRadius(Rect face) => math.max(face.width, face.height) * 0.78;

/// Samaritan's symbol around [center] with main circle radius [r]; the
/// geometry follows the show's artwork, where that circle has radius 380.
void paintSamaritanMark(
  Canvas canvas,
  Offset center,
  double r,
  SamaritanMark mark, {
  double opacity = 1,
  double seconds = 0,
  String? readout,
  TextCache? text,
}) {
  final k = r / 380;
  final c = center;
  Paint stroke(Color color, double width, double alpha) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(width * k, 1)
    ..color = color.withValues(alpha: alpha * opacity);
  Paint fill(Color color, double alpha) => Paint()..color = color.withValues(alpha: alpha * opacity);
  const white = SamaritanColors.white, red = SamaritanColors.red;
  final enemy = mark == SamaritanMark.enemy;

  // Translucent ring bands.
  canvas
    ..drawCircle(c, 381 * k, stroke(Colors.black, 72, enemy ? 0.12 : 0.3))
    ..drawCircle(c, 314 * k, stroke(enemy ? red : white, 62, enemy ? 0.12 : 0.3))
    ..drawCircle(c, 25 * k, stroke(white, 2, 0.35));
  // Grey bars and dots along the axes.
  final bars = stroke(const Color(0xFF404040), 12, 0.5);
  canvas
    ..drawLine(c + Offset(190 * k, 0), c + Offset(260 * k, 0), bars)
    ..drawLine(c - Offset(190 * k, 0), c - Offset(260 * k, 0), bars);
  for (final d in [Offset(115 * k, 0), Offset(-115 * k, 0), Offset(0, 115 * k), Offset(0, -115 * k)]) {
    canvas.drawRect(Rect.fromCenter(center: c + d, width: 6 * k + 1, height: 6 * k + 1), fill(white, 1));
  }
  // Inner brackets ( ) on the light band.
  final bracket = Path()
    ..moveTo(286.94, 87.72)
    ..lineTo(310.81, 95.03)
    ..cubicTo(329.75, 33.1, 329.75, -33.1, 310.81, -95.03)
    ..lineTo(286.94, -87.72);
  for (final turn in [0.0, math.pi]) {
    final m = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(turn)
      ..scaleByDouble(k, k, 1, 1);
    canvas.drawPath(bracket.transform(m.storage), stroke(Colors.black, 5, 0.5));
  }
  // Main circle.
  canvas.drawCircle(c, (enemy ? 322 : 380) * k, stroke(enemy ? red : white, enemy ? 8 : 4, enemy ? 0.8 : 1));
  // Short outer arcs, slowly sweeping round.
  final sweep = seconds * 0.35;
  final arcs = stroke(white, 8, enemy ? 0.4 : 1);
  final outer = Rect.fromCircle(center: c, radius: 455 * k);
  canvas
    ..drawArc(outer, sweep - 0.384, 0.768, false, arcs)
    ..drawArc(outer, sweep + math.pi - 0.384, 0.768, false, arcs);
  // Faint frame with open corners and small crosses.
  final frame = stroke(white, 2, 0.3);
  for (var turn = 0; turn < 4; turn++) {
    final a = turn * math.pi / 2;
    Offset rot(double x, double y) => c + Offset(x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)) * k;
    canvas
      ..drawLine(rot(434, -384), rot(434, 384), frame)
      ..drawLine(rot(-446, 434), rot(-422, 434), frame)
      ..drawLine(rot(-434, 422), rot(-434, 446), frame);
  }
  // Readout below the frame, bottom left.
  if (readout != null && text != null) {
    canvas
      ..drawRect(Rect.fromLTWH(c.dx - 418 * k, c.dy + 394 * k, 18 * k + 2, 9 * k + 1), fill(white, 0.5))
      ..drawRect(Rect.fromLTWH(c.dx - 418 * k, c.dy + 410 * k, 18 * k + 2, 9 * k + 1), stroke(white, 2, 0.5));
    final painter = text.layout(
      readout,
      TextStyle(fontFamily: kSamaritanFont, fontSize: math.max(32 * k, 9), color: white.withValues(alpha: 0.5 * opacity)),
    );
    painter.paint(canvas, Offset(c.dx - 388 * k, c.dy + 420 * k - painter.height));
  }

  Path triangle(double scale) {
    final m = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(k * scale, k * scale, 1, 1);
    return (Path()
          ..moveTo(242.49, -140)
          ..lineTo(0, 280)
          ..lineTo(-242.49, -140)
          ..close())
        .transform(m.storage);
  }

  switch (mark) {
    case SamaritanMark.tracked:
      break;
    case SamaritanMark.target:
      canvas.drawPath(triangle(1), stroke(red, 18, 0.8)..strokeJoin = StrokeJoin.miter);
    case SamaritanMark.priorityTarget:
      final pulse = 0.5 + 0.5 * math.sin(seconds * 4);
      canvas
        ..drawPath(triangle(1), stroke(red, 18, 0.55)..strokeJoin = StrokeJoin.miter)
        ..drawPath(triangle(1.18 + 0.1 * pulse), stroke(red, 18, 0.45 + 0.3 * pulse)..strokeJoin = StrokeJoin.miter);
    case SamaritanMark.deviant:
      final ticks = stroke(red, 18, 0.8);
      for (final (sx, sy) in const [(1, -1), (1, 1), (-1, 1), (-1, -1)]) {
        canvas.drawLine(c + Offset(125 * k * sx, 125 * k * sy), c + Offset(175 * k * sx, 175 * k * sy), ticks);
      }
      canvas
        ..drawArc(Rect.fromCircle(center: c, radius: 425 * k), -2.705, 0.611, false, stroke(white, 46, 0.5))
        ..drawLine(c + Offset(210 * k, -317 * k), c + Offset(210 * k, 317 * k), stroke(white, 3, 0.75))
        ..drawRect(Rect.fromLTWH(c.dx + 492 * k, c.dy - 20 * k, 40 * k, 40 * k), stroke(white, 6, 1));
    case SamaritanMark.enemy:
      final band = stroke(red, 46, 0.33);
      final inner = Rect.fromCircle(center: c, radius: 270 * k);
      canvas
        ..drawArc(inner, -0.384, 0.768, false, band)
        ..drawArc(inner, math.pi - 0.384, 0.768, false, band)
        ..drawCircle(c, 486 * k, stroke(red, 3, 0.15))
        ..drawCircle(c, 511 * k, stroke(red, 3, 0.15));
      final ticks = stroke(red, 16, 0.8);
      for (final (sx, sy) in const [(1, -1), (1, 1), (-1, 1), (-1, -1)]) {
        canvas
          ..drawLine(c + Offset(160 * k * sx, 160 * k * sy), c + Offset(205 * k * sx, 205 * k * sy), ticks)
          ..drawRect(Rect.fromCenter(center: c + Offset(308 * k * sx, 308 * k * sy), width: 16 * k, height: 16 * k), fill(red, 0.8));
      }
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - 367 * k)
          ..lineTo(c.dx - 31 * k, c.dy - 421 * k)
          ..lineTo(c.dx + 31 * k, c.dy - 421 * k)
          ..close(),
        stroke(red, 6, 0.8),
      );
  }
}

/// Reuses laid-out text between frames; the overlay repaints at display rate.
class TextCache {
  final _painters = <String, TextPainter>{};

  TextPainter layout(String text, TextStyle style) {
    final key = '${style.fontFamily}|${style.fontSize}|${style.color?.toARGB32()}|${style.letterSpacing}|'
        '${style.fontWeight?.value}|$text';
    final cached = _painters[key];
    if (cached != null) return cached;
    if (_painters.length > 400) clear();
    return _painters[key] = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

/// Draws [image] upscaled without smoothing, so every pixel shows as a block.
void paintBlocks(Canvas canvas, ui.Image image, Rect destination, {double opacity = 1}) {
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    destination,
    Paint()
      ..filterQuality = FilterQuality.none
      ..color = Colors.white.withValues(alpha: opacity),
  );
}

/// Green of the Machine's aircraft triangles.
const kAircraftGreen = Color(0xFF3CD65A);

/// The Machine's marks for things: wheeled vehicles get a box with solid
/// vertical sides and a central target, watercraft a diamond, aircraft a
/// green triangle. Samaritan circles them with a small box in the middle.
void paintThingMark(Canvas canvas, Rect r, ThingKind kind, {double opacity = 1, bool samaritan = false}) {
  final white = Colors.white.withValues(alpha: opacity);
  final shadow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.5
    ..color = Colors.black.withValues(alpha: 0.3 * opacity);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = white;
  void draw(Path path, Paint paint) => canvas
    ..drawPath(path, shadow)
    ..drawPath(path, paint);
  final c = r.center;
  final target = math.max(6.0, r.shortestSide * 0.06);
  final targetPath = Path()
    ..addOval(Rect.fromCircle(center: c, radius: target))
    ..moveTo(c.dx - target * 2, c.dy)
    ..lineTo(c.dx - target, c.dy)
    ..moveTo(c.dx + target, c.dy)
    ..lineTo(c.dx + target * 2, c.dy)
    ..moveTo(c.dx, c.dy - target * 2)
    ..lineTo(c.dx, c.dy - target)
    ..moveTo(c.dx, c.dy + target)
    ..lineTo(c.dx, c.dy + target * 2);

  if (samaritan) {
    final radius = r.longestSide * 0.6;
    draw(Path()..addOval(Rect.fromCircle(center: c, radius: radius)), line);
    draw(Path()..addOval(Rect.fromCircle(center: c, radius: radius * 0.82)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..color = Colors.white.withValues(alpha: 0.18 * opacity));
    draw(Path()..addRect(Rect.fromCenter(center: c, width: radius * 0.35, height: radius * 0.35)), line);
    return;
  }

  switch (kind) {
    case ThingKind.vehicle:
      final solid = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.left, r.bottom)
        ..moveTo(r.right, r.top)
        ..lineTo(r.right, r.bottom);
      final dashes = Path();
      for (var x = r.left; x < r.right; x += 12) {
        final end = math.min(x + 6, r.right);
        dashes
          ..moveTo(x, r.top)
          ..lineTo(end, r.top)
          ..moveTo(x, r.bottom)
          ..lineTo(end, r.bottom);
      }
      draw(solid, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = white);
      draw(dashes, line);
      draw(targetPath, line);
    case ThingKind.watercraft:
      final diamond = Path()
        ..moveTo(c.dx, r.top)
        ..lineTo(r.right, c.dy)
        ..lineTo(c.dx, r.bottom)
        ..lineTo(r.left, c.dy)
        ..close();
      draw(diamond, line);
      draw(targetPath, line);
    case ThingKind.aircraft:
      final green = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = kAircraftGreen.withValues(alpha: opacity);
      draw(
        Path()
          ..moveTo(c.dx, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close(),
        green,
      );
  }
}
