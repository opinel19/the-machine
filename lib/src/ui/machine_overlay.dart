import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../machine/subject.dart';
import '../machine/thing.dart';
import '../storage/settings.dart';
import '../theme.dart';
import 'box_painter.dart';
import 'enhance.dart';
import 'simulation_view.dart';

/// Draws each system's marks over the camera feed and handles gestures on
/// them: tap flags a subject as relevant (or, on a threat, runs a
/// simulation), double tap zooms in ("enhance"), long press opens the
/// designation menu.
class MachineOverlay extends StatefulWidget {
  const MachineOverlay({
    super.key,
    required this.controller,
    required this.enhance,
    required this.onDesignate,
    required this.onSimulate,
  });

  final MachineController controller;
  final EnhanceState enhance;
  final void Function(Subject subject) onDesignate;
  final void Function(Subject subject) onSimulate;

  @override
  State<MachineOverlay> createState() => _MachineOverlayState();
}

class _MachineOverlayState extends State<MachineOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = _RepaintSignal();
  final _marks = <int, _Mark>{};
  final _thingMarks = <int, _ThingMark>{};
  final _text = TextCache();
  Duration _lastTick = Duration.zero;
  double _seconds = 0;
  Size _view = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    _text.clear();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;
    _seconds += dt;
    final controller = widget.controller;
    // Detections arrive at camera rate; ease marks toward them at display rate.
    final follow = 1 - math.exp(-dt * 16);
    final present = <int>{};
    for (final subject in controller.subjects) {
      present.add(subject.id);
      final mark = _marks[subject.id];
      if (mark == null) {
        _marks[subject.id] = _Mark(subject, subject.box);
      } else {
        mark
          ..subject = subject
          ..face = Rect.lerp(mark.face, subject.box, follow)!
          ..lost = 0
          ..advance(dt);
      }
    }
    _marks.removeWhere((id, mark) {
      if (present.contains(id)) return false;
      mark.lost += dt;
      return mark.lost >= _Mark.fadeOutSeconds;
    });
    final seenThings = <int>{};
    for (final thing in controller.things) {
      seenThings.add(thing.id);
      final mark = _thingMarks[thing.id];
      if (mark == null) {
        _thingMarks[thing.id] = _ThingMark(thing, thing.box);
      } else {
        mark
          ..thing = thing
          ..box = Rect.lerp(mark.box, thing.box, 1 - math.exp(-dt * 10))!
          ..age += dt
          ..lost = 0;
      }
    }
    _thingMarks.removeWhere((id, mark) {
      if (seenThings.contains(id)) return false;
      mark.lost += dt;
      return mark.lost >= _Mark.fadeOutSeconds;
    });
    final enhance = widget.enhance;
    if (enhance.active) {
      final subject = controller.subjects.where((s) => s.id == enhance.subjectId).firstOrNull;
      enhance.tick(dt, subject, controller.frameSize, _view);
    }
    _repaint.fire();
  }

  FrameMapping? _mapping() {
    final frame = widget.controller.frameSize;
    if (frame == null || _view.isEmpty) return null;
    final enhance = widget.enhance;
    return FrameMapping(
      frame,
      _view,
      mirror: widget.controller.mirrorOverlay,
      zoom: enhance.zoom,
      pan: enhance.pan,
    );
  }

  _Mark? _hit(Offset position) {
    final mapping = _mapping();
    if (mapping == null) return null;
    _Mark? hit;
    var hitSize = double.infinity;
    for (final mark in _marks.values) {
      if (mark.lost > 0) continue;
      final area = mapping.rect(headSquare(mark.face)).inflate(12);
      if (area.contains(position) && area.width < hitSize) {
        hit = mark;
        hitSize = area.width;
      }
    }
    return hit;
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.enhance.active) {
      widget.enhance.stop();
      return;
    }
    final hit = _hit(details.localPosition);
    if (hit == null) return;
    HapticFeedback.selectionClick();
    if (simulatesOnTap(hit.subject)) {
      widget.onSimulate(hit.subject);
    } else {
      widget.controller.toggleRelevant(hit.subject.id);
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final enhance = widget.enhance;
    final hit = _hit(details.localPosition);
    if (enhance.active && (hit == null || hit.subject.id == enhance.subjectId)) {
      enhance.stop();
    } else if (hit != null) {
      HapticFeedback.mediumImpact();
      enhance.start(hit.subject.id);
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final hit = _hit(details.localPosition);
    if (hit == null) return;
    HapticFeedback.heavyImpact();
    widget.onDesignate(hit.subject);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _view = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: () {},
          onLongPressStart: _onLongPressStart,
          child: CustomPaint(
            size: Size.infinite,
            painter: _OverlayPainter(
              controller: widget.controller,
              marks: _marks,
              thingMarks: _thingMarks,
              text: _text,
              padding: MediaQuery.paddingOf(context),
              mapping: _mapping,
              seconds: () => _seconds,
              repaint: _repaint,
            ),
          ),
        );
      },
    );
  }
}

class _RepaintSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// On-screen state of one subject's mark.
class _Mark {
  _Mark(this.subject, this.face);

  static const fadeOutSeconds = 0.3;

  /// How long every new face shows ANALYZING before its verdict appears.
  static const analyzeSeconds = 0.6;

  Subject subject;

  /// Smoothed face box in frame pixels.
  Rect face;
  double age = 0;
  double lost = 0;
  Designation shown = Designation.analyzing;
  double sinceChange = 0;

  void advance(double dt) {
    age += dt;
    sinceChange += dt;
    final wanted = age < analyzeSeconds ? Designation.analyzing : subject.displayDesignation;
    if (wanted != shown) {
      shown = wanted;
      sinceChange = 0;
    }
  }

  /// Lock-on: marks snap in from larger as the face is acquired.
  double get grow => 1 + (1 - Curves.easeOutCubic.transform((age / 0.35).clamp(0.0, 1.0))) * 0.8;

  double get opacity {
    var o = (age / 0.12).clamp(0.0, 1.0) * (1 - lost / fadeOutSeconds).clamp(0.0, 1.0);
    final waiting = shown == Designation.analyzing || shown == Designation.verifying;
    if (waiting && (age * 5).floor().isOdd) o *= 0.45;
    return o;
  }
}

/// On-screen state of a vehicle, boat or aircraft.
class _ThingMark {
  _ThingMark(this.thing, this.box);

  Thing thing;
  Rect box;
  double age = 0;
  double lost = 0;

  double get opacity =>
      (age / 0.2).clamp(0.0, 1.0) * (1 - lost / _Mark.fadeOutSeconds).clamp(0.0, 1.0);
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.controller,
    required this.marks,
    required this.thingMarks,
    required this.text,
    required this.padding,
    required this.mapping,
    required this.seconds,
    required super.repaint,
  });

  final MachineController controller;
  final Map<int, _Mark> marks;
  final Map<int, _ThingMark> thingMarks;
  final TextCache text;
  final EdgeInsets padding;
  final FrameMapping? Function() mapping;
  final double Function() seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final map = mapping();
    if (map == null) return;
    final samaritan = controller.settings.mode == MachineMode.samaritan;
    for (final mark in thingMarks.values) {
      _paintThing(canvas, map, mark, samaritan);
    }
    for (final mark in marks.values) {
      if (mark.opacity <= 0.01) continue;
      if (samaritan) {
        _paintSamaritan(canvas, map, mark);
      } else {
        _paintMachine(canvas, size, map, mark);
      }
    }
  }

  void _paintThing(Canvas canvas, FrameMapping map, _ThingMark mark, bool samaritan) {
    final opacity = mark.opacity;
    if (opacity <= 0.01) return;
    final rect = map.rect(mark.box);
    final thing = mark.thing;
    paintThingMark(canvas, rect, thing.kind, opacity: opacity, samaritan: samaritan);
    final textOpacity = (opacity * 8).round() / 8;
    final aircraft = thing.kind == ThingKind.aircraft;
    final color = (aircraft && !samaritan ? kAircraftGreen : Colors.white).withValues(alpha: textOpacity);
    final title = text.layout(
      samaritan ? thing.kind.label : '${thing.kind.label} // ${thing.label}',
      samaritan
          ? TextStyle(fontFamily: kSamaritanFont, fontSize: 11, letterSpacing: 2.5, color: color, fontWeight: FontWeight.w600)
          : machineStyle(size: 11, color: color, spacing: 1.5, height: 1),
    );
    final sub = text.layout(
      aircraft ? 'FLT ${thing.code}' : thing.code,
      samaritan
          ? TextStyle(fontFamily: kSamaritanFont, fontSize: 9, letterSpacing: 2, color: color)
          : machineStyle(size: 9, color: color, spacing: 1.2, height: 1),
    );
    final origin = Offset(rect.left, rect.bottom + 5);
    title.paint(canvas, origin);
    sub.paint(canvas, origin + Offset(0, title.height + 2));
  }

  List<String> _details(_Mark mark) {
    final subject = mark.subject;
    final settings = controller.settings;
    final designation = mark.shown;
    return [
      subject.code,
      // Known by build and walk: no face in view.
      if (subject.rear) 'GAIT ANALYSIS',
      if (subject.issuedNumber != null) 'SSN ${subject.issuedNumber}',
      if (settings.showScores)
        'SIM ${subject.similarity.toStringAsFixed(2)} · N${subject.embeddings.length} · SH${subject.sharpness.round()}'
      else if (subject.identity != null && designation.settled)
        'MATCH ${(subject.similarity * 100).clamp(0, 100).toStringAsFixed(0)}%',
    ];
  }

  void _paintMachine(Canvas canvas, Size size, FrameMapping map, _Mark mark) {
    final designation = mark.shown;
    final opacity = mark.opacity;
    // Alpha is quantised because laid-out text is cached per colour.
    final textOpacity = (opacity * 8).round() / 8;
    var box = map.rect(headSquare(mark.face));
    box = Rect.fromCenter(center: box.center, width: box.width * mark.grow, height: box.height * mark.grow);

    final colors = BoxColors.of(designation);
    paintMachineBox(
      canvas,
      box,
      colors,
      opacity: opacity,
      solidEdges: designation == Designation.threat,
      season: BoxSeason.values[controller.settings.season - 1],
    );

    // A verdict "pings": an outline expands from the box and fades.
    if (designation.settled && mark.sinceChange < 0.45) {
      final t = mark.sinceChange / 0.45;
      canvas.drawRect(
        box.inflate(box.width * 0.22 * Curves.easeOut.transform(t)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.corners.withValues(alpha: opacity * (1 - t) * 0.9),
      );
    }

    // Designation tab, typed out like the Machine's text.
    final label = designation.label(MachineMode.machine);
    final typed = math.min(label.length, (mark.sinceChange * 30).floor());
    final cursor = (mark.sinceChange * 6).floor().isEven ? '_' : ' ';
    final tabColor = BoxColors.tabOf(designation);
    final blinkOff = designation == Designation.threat && (mark.age * 3).floor().isOdd;
    final ink = BoxColors.inkOn(tabColor).withValues(alpha: textOpacity);
    final tabStyle = machineStyle(size: 12, color: designation == Designation.personOfInterest ? MachineColors.admin.withValues(alpha: textOpacity) : ink, spacing: 1.8, height: 1);
    final tabText = text.layout(typed < label.length ? label.substring(0, typed) + cursor : label, tabStyle);
    const padX = 6.0, padY = 3.0;
    final tabSize = Size(text.layout(label, tabStyle).width + padX * 2, tabText.height + padY * 2);
    var tabTop = box.top - tabSize.height - 5;
    final tabBelow = tabTop < padding.top + 2;
    if (tabBelow) tabTop = box.bottom + 5;
    final tabLeft = box.left.clamp(4.0, math.max(4.0, size.width - tabSize.width - 4)).toDouble();
    final tab = Offset(tabLeft, tabTop) & tabSize;
    if (!blinkOff) {
      canvas.drawRect(tab, Paint()..color = tabColor.withValues(alpha: opacity));
      if (designation == Designation.personOfInterest) {
        canvas.drawRect(
          tab,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = MachineColors.admin.withValues(alpha: opacity),
        );
      }
      tabText.paint(canvas, tab.topLeft + const Offset(padX, padY));
    }

    // Details under the box: whose face it is, then the numbers.
    final lineColor = (tabColor == Colors.black ? MachineColors.irrelevant : tabColor).withValues(alpha: textOpacity * 0.9);
    var y = (tabBelow ? tab.bottom : box.bottom) + 5;
    final name = designation.settled ? mark.subject.identity?.name : null;
    if (name != null) {
      final nameStyle = machineStyle(size: 13, color: lineColor, spacing: 2, height: 1);
      final shownChars = ((mark.sinceChange * 30).floor() - label.length).clamp(0, name.length);
      text.layout(name.substring(0, shownChars), nameStyle).paint(canvas, Offset(tabLeft, y));
      y += text.layout(name, nameStyle).height + 4;
    }
    final detailStyle = machineStyle(size: 10, color: lineColor, spacing: 1.2, height: 1);
    for (final line in _details(mark)) {
      final painter = text.layout(line, detailStyle);
      painter.paint(canvas, Offset(tabLeft, y));
      y += painter.height + 3;
    }
  }

  void _paintSamaritan(Canvas canvas, FrameMapping map, _Mark mark) {
    final designation = mark.shown;
    final opacity = mark.opacity;
    final textOpacity = (opacity * 8).round() / 8;
    final symbol = SamaritanMark.of(designation);
    final circle = map.rect(Rect.fromCircle(center: mark.face.center, radius: samaritanRadius(mark.face)));
    final r = circle.width / 2 * mark.grow;
    final distance = mark.subject.distanceMeters(controller.focalPixels);
    paintSamaritanMark(
      canvas,
      circle.center,
      r,
      symbol,
      opacity: opacity,
      seconds: seconds(),
      readout: '${distance.toStringAsFixed(2)} M',
      text: text,
    );

    // Label under the mark, name and numbers below it.
    final color = (symbol.red ? SamaritanColors.red : SamaritanColors.white).withValues(alpha: textOpacity);
    final label = designation.label(MachineMode.samaritan);
    final words = label.split(' ');
    // Samaritan's text appears a word at a time.
    final shownWords = math.min(words.length, 1 + (mark.sinceChange * 5).floor());
    final labelStyle = TextStyle(
      fontFamily: kSamaritanFont,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 3,
      color: color,
    );
    final labelPainter = text.layout(words.take(shownWords).join(' '), labelStyle);
    final top = circle.center.dy + r * 1.2 + 6;
    labelPainter.paint(canvas, Offset(circle.center.dx - text.layout(label, labelStyle).width / 2, top));
    var y = top + labelPainter.height + 3;
    final lines = [
      if (designation.settled) ?mark.subject.identity?.name,
      ..._details(mark),
    ];
    final detailStyle = TextStyle(
      fontFamily: kSamaritanFont,
      fontSize: 10,
      letterSpacing: 2,
      color: SamaritanColors.white.withValues(alpha: textOpacity * 0.75),
    );
    for (final line in lines) {
      final painter = text.layout(line, detailStyle);
      painter.paint(canvas, Offset(circle.center.dx - painter.width / 2, y));
      y += painter.height + 2;
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) => oldDelegate.padding != padding;
}
