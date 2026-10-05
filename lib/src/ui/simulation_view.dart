import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../machine/oracle.dart';
import '../machine/simulation.dart';
import '../machine/subject.dart';
import '../storage/settings.dart';
import '../theme.dart';
import '../vision/image_codec.dart';
import 'box_painter.dart';
import 'hud.dart';

/// Simulates what happens to [subject] (the user, when null) and plays it
/// back full screen: courses of action branch off and fail, the counter
/// races through hundreds of thousands of runs, and the system settles on
/// one course. Tap to skip to the verdict.
Future<void> showSimulation(BuildContext context, MachineController controller, {Subject? subject}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => _SimulationView(controller: controller, subject: subject),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  );
}

/// When each part of the playback happens, in seconds.
abstract final class _Timeline {
  static const intro = 0.7;
  static const runs = [1.1, 0.9, 0.75, 0.6];
  static const fastForward = 1.4;
  static const chosen = 1.3;
  static const typing = 1.8;

  /// Share of a run spent growing its path; the rest shows how it ended.
  static const growing = 0.7;

  static double runStart(int run) => intro + runs.take(run).fold(0.0, (a, b) => a + b);
  static final fastForwardStart = runStart(runs.length);
  static final chosenStart = fastForwardStart + fastForward;
  static final outcomeStart = chosenStart + chosen;
  static final end = outcomeStart + typing;
}

class _SimulationView extends StatefulWidget {
  const _SimulationView({required this.controller, this.subject});

  final MachineController controller;
  final Subject? subject;

  @override
  State<_SimulationView> createState() => _SimulationViewState();
}

class _SimulationViewState extends State<_SimulationView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final String _label;
  late final Designation _designation;
  late final int _seed;
  late SimulationPlan _plan;
  int _attempt = 0;
  Duration _elapsed = Duration.zero;
  Duration _startedAt = Duration.zero;
  final _felt = <int>{};
  bool _reported = false;
  Uint8List? _face;

  double get _t => (_elapsed - _startedAt).inMicroseconds / 1e6;

  bool get _samaritan => widget.controller.settings.mode == MachineMode.samaritan;

  @override
  void initState() {
    super.initState();
    final subject = widget.subject;
    _label = subject == null ? 'USER' : subject.identity?.name ?? subject.code;
    // The user gets the treatment a number gets.
    _designation = subject?.displayDesignation ?? Designation.relevant;
    _seed = subject?.number ?? DateTime.now().day;
    _plan = _generate();
    _ticker = createTicker(_tick)..start();
    unawaited(_cropFace());
    _begin();
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(widget.controller.native.stopSound());
    super.dispose();
  }

  SimulationPlan _generate() => SimulationPlan.generate(
    subject: _label,
    designation: _designation,
    mode: widget.controller.settings.mode,
    seed: _seed,
    attempt: _attempt,
  );

  void _begin() {
    widget.controller.simulationStarted(_label);
    unawaited(widget.controller.native.playSound('assets/sounds/simulation.wav'));
  }

  /// The subject's head from the latest frame, face or not.
  Future<void> _cropFace() async {
    final subject = widget.subject;
    final frame = widget.controller.lastFrame;
    if (subject == null || frame == null) return;
    const side = 96;
    final png = await encodePng(frame.regionRgba(headSquare(subject.box), side, side), side, side);
    if (mounted) setState(() => _face = png);
  }

  void _tick(Duration elapsed) {
    setState(() => _elapsed = elapsed);
    final t = _t;
    // A tap on the glass for every course that ends.
    for (var k = 0; k < _plan.runs.length; k++) {
      final start = k < SimulationPlan.failedRuns ? _Timeline.runStart(k) : _Timeline.chosenStart;
      final length = k < SimulationPlan.failedRuns ? _Timeline.runs[k] : _Timeline.chosen;
      if (t >= start + length * _Timeline.growing && _felt.add(k)) {
        unawaited(k < SimulationPlan.failedRuns ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact());
      }
    }
    if (!_reported && t >= _Timeline.outcomeStart) {
      _reported = true;
      widget.controller.reportSimulation(_plan);
    }
  }

  void _skip() {
    if (_t >= _Timeline.outcomeStart) return;
    _startedAt = _elapsed - Duration(microseconds: (_Timeline.outcomeStart * 1e6).round());
    _felt.addAll(List.generate(_plan.runs.length, (i) => i));
    unawaited(widget.controller.native.stopSound());
  }

  void _runAgain() {
    setState(() {
      _attempt++;
      _plan = _generate();
      _startedAt = _elapsed;
      _felt.clear();
      _reported = false;
    });
    _begin();
  }

  Future<void> _markIrrelevant() async {
    final subject = widget.subject;
    if (subject == null) return;
    Navigator.pop(context);
    await widget.controller.designate(subject.id, Designation.irrelevant);
  }

  /// The run on screen and how far along it is (0-1); null between runs.
  (SimulationRun, double)? _current() {
    final t = _t;
    for (var k = 0; k < SimulationPlan.failedRuns; k++) {
      final start = _Timeline.runStart(k);
      if (t >= start && t < start + _Timeline.runs[k]) return (_plan.runs[k], (t - start) / _Timeline.runs[k]);
    }
    if (t >= _Timeline.chosenStart) return (_plan.chosen, ((t - _Timeline.chosenStart) / _Timeline.chosen).clamp(0.0, 1.0));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.controller.settings.theme;
    final samaritan = _samaritan;
    final ink = samaritan ? SamaritanColors.ink : MachineColors.text;
    final dim = samaritan ? const Color(0x99111111) : MachineColors.dim;
    final t = _t;
    final done = t >= _Timeline.end;
    final subject = widget.subject;
    final flagged = subject?.identity != null && subject?.identity?.designation != Designation.admin;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: Material(
        color: samaritan ? SamaritanColors.paper : Colors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (samaritan) ...[const SamaritanTriangle(), const SizedBox(width: 10)],
                    Expanded(
                      child: Text(
                        samaritan ? 'SAMARITAN // PREDICTIVE ANALYSIS' : 'THE MACHINE // SIMULATION',
                        style: theme.style(size: 13, color: theme.accent, spacing: samaritan ? 2 : theme.spacing * 1.5),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: ink)),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _subjectPanel(theme, ink, dim),
                ),
                const SizedBox(height: 10),
                Text(_counter(), style: theme.style(size: 12, color: ink, spacing: 1.5)),
                const SizedBox(height: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TreePainter(plan: _plan, t: t, samaritan: samaritan, accent: theme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(height: 64, child: _trace(theme, ink, dim)),
                SizedBox(height: 118, child: _outcome(theme, ink, dim)),
                SizedBox(
                  height: 40,
                  child: AnimatedOpacity(
                    opacity: done ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: IgnorePointer(
                      ignoring: !done,
                      child: Row(
                        children: [
                          _button('RUN AGAIN', theme, ink, _runAgain),
                          if (flagged) _button(samaritan ? 'CLEAR' : 'MARK IRRELEVANT', theme, theme.alert, _markIrrelevant),
                          _button('CLOSE', theme, ink, () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _subjectPanel(ModeTheme theme, Color ink, Color dim) {
    final face = _face;
    final place = widget.controller.location.place;
    return Row(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(7),
                child: face == null
                    ? Icon(Icons.person_outline, color: dim, size: 30)
                    : Image.memory(face, fit: BoxFit.cover, gaplessPlayback: true),
              ),
              CustomPaint(painter: _SubjectMark(_designation, samaritan: _samaritan)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_label, style: theme.style(size: 17, color: ink, spacing: 2), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                widget.subject == null ? 'SUBJECT: USER' : 'CLASS: ${_designation.label(widget.controller.settings.mode)}',
                style: theme.style(size: 10, color: dim, spacing: 1.2),
              ),
              if (place != null) Text('LOCATION: $place', style: theme.style(size: 10, color: dim, spacing: 1.2)),
            ],
          ),
        ),
      ],
    );
  }

  String _counter() {
    final t = _t;
    if (t < _Timeline.intro) {
      return '${_samaritan ? 'INITIATING ANALYSIS' : 'INITIATING SIMULATION'}${(t * 6).floor().isEven ? '_' : ''}';
    }
    int index;
    if (t >= _Timeline.fastForwardStart && t < _Timeline.chosenStart) {
      // Races through the runs in between, faster and faster.
      final p = Curves.easeIn.transform((t - _Timeline.fastForwardStart) / _Timeline.fastForward);
      final from = math.log(_plan.runs[SimulationPlan.failedRuns - 1].index);
      final to = math.log(_plan.chosen.index);
      index = math.exp(from + (to - from) * p).round();
    } else {
      index = (_current()?.$1 ?? _plan.chosen).index;
    }
    return '${_samaritan ? 'SCENARIO' : 'SIMULATION'} ${_grouped(index)} OF ${_grouped(_plan.total)}';
  }

  /// The run on screen, step by step, and how it ended.
  Widget _trace(ModeTheme theme, Color ink, Color dim) {
    final t = _t;
    final failed = _samaritan ? const Color(0x99111111) : MachineColors.relevant;
    final lines = <(String, Color)>[];
    if (t >= _Timeline.fastForwardStart && t < _Timeline.chosenStart) {
      final random = math.Random((t * 16).floor());
      final path = [for (final b in SimulationPlan.branching) random.nextInt(b)];
      final steps = [
        for (var level = 0; level < path.length; level++) _plan.actions[level][SimulationPlan.nodeIndex(path, level)],
      ];
      lines.add(('> ${steps.join(' > ')}', dim));
    } else if (_current() case (final run, final p)) {
      final steps = _plan.stepsOf(run);
      final color = run.success ? theme.accent : ink;
      final shown = (p / _Timeline.growing * steps.length).ceil().clamp(1, steps.length);
      for (var i = 0; i < shown; i++) {
        lines.add(('${'  ' * i}> ${steps[i]}', color));
      }
      if (p >= _Timeline.growing) {
        lines.add((
          '${'  ' * steps.length}${run.outcome} · P ${run.probability.toStringAsFixed(2)}',
          run.success ? theme.accent : failed,
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (text, color) in lines)
          Text(text, style: theme.style(size: 11, color: color, spacing: 1.2), maxLines: 1, overflow: TextOverflow.clip),
      ],
    );
  }

  /// The verdict, typed out.
  Widget _outcome(ModeTheme theme, Color ink, Color dim) {
    final t = _t;
    if (t < _Timeline.outcomeStart) return const SizedBox.shrink();
    final plan = _plan;
    final survival = plan.metric == 'PROBABILITY OF SURVIVAL';
    final bad = survival ? plan.percent < 50 : plan.percent >= 50;
    final lines = <(String, TextStyle)>[
      (
        '${_samaritan ? 'SCENARIOS EVALUATED' : 'SIMULATIONS COMPLETE'}: ${_grouped(plan.total)}',
        theme.style(size: 10, color: dim, spacing: 1.2),
      ),
      (plan.verdict, theme.style(size: 12, color: ink, spacing: 1.5)),
      (
        '${plan.metric}: ${plan.percent}%',
        theme.style(size: 19, color: bad ? theme.alert : theme.accent, spacing: 1.5, weight: FontWeight.w600),
      ),
      ('${_samaritan ? 'DIRECTIVE' : 'OPTIMAL COURSE'}: ${plan.course}', theme.style(size: 10, color: ink, spacing: 1.2)),
      ('${plan.courseLabel}: ${plan.coursePercent}%', theme.style(size: 12, color: theme.accent, spacing: 1.5)),
    ];
    var budget = ((t - _Timeline.outcomeStart) * 90).floor();
    final shown = <Widget>[];
    for (final (text, style) in lines) {
      if (budget <= 0) break;
      shown.add(Text(text.substring(0, math.min(text.length, budget)), style: style, maxLines: 2));
      budget -= text.length;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: shown);
  }

  Widget _button(String label, ModeTheme theme, Color color, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 18),
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('> $label', style: theme.style(size: 12, color: color, spacing: 1.5)),
      ),
    ),
  );

  static String _grouped(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

/// The subject's box (or Samaritan's mark) around their picture.
class _SubjectMark extends CustomPainter {
  const _SubjectMark(this.designation, {required this.samaritan});

  final Designation designation;
  final bool samaritan;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    if (samaritan) {
      paintSamaritanMark(canvas, rect.center, rect.width * 0.42, SamaritanMark.of(designation));
    } else {
      paintMachineBox(canvas, rect, BoxColors.of(designation), solidEdges: designation == Designation.threat);
    }
  }

  @override
  bool shouldRepaint(_SubjectMark old) => old.designation != designation || old.samaritan != samaritan;
}

/// Where the nodes of the decision tree sit: the subject on top, one row
/// per decision below.
class _TreeLayout {
  _TreeLayout(this.size);

  final Size size;
  static const _top = 8.0;
  static const _bottom = 10.0;
  static const _margin = 6.0;

  Offset get root => Offset(size.width / 2, _top);

  static int count(int level) {
    var n = 1;
    for (var l = 0; l <= level; l++) {
      n *= SimulationPlan.branching[l];
    }
    return n;
  }

  Offset node(int level, int index) {
    final y = _top + (size.height - _top - _bottom) * (level + 1) / SimulationPlan.branching.length;
    return Offset(_margin + (index + 0.5) * (size.width - 2 * _margin) / count(level), y);
  }

  /// Root to leaf along [path], as right-angled segments.
  List<Offset> polyline(List<int> path) {
    final points = [root];
    var from = root;
    for (var level = 0; level < path.length; level++) {
      final to = node(level, SimulationPlan.nodeIndex(path, level));
      final mid = (from.dy + to.dy) / 2;
      points.addAll([Offset(from.dx, mid), Offset(to.dx, mid), to]);
      from = to;
    }
    return points;
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter({required this.plan, required this.t, required this.samaritan, required this.accent});

  final SimulationPlan plan;
  final double t;
  final bool samaritan;
  final Color accent;

  Color get _ink => samaritan ? SamaritanColors.ink : Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = _TreeLayout(size);
    final appear = (t / _Timeline.intro).clamp(0.0, 1.0);

    // Every course it could take, faint.
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _ink.withValues(alpha: 0.12 * appear);
    final dots = Paint()..color = _ink.withValues(alpha: 0.3 * appear);
    for (var level = 0; level < SimulationPlan.branching.length; level++) {
      for (var i = 0; i < _TreeLayout.count(level); i++) {
        final parent = level == 0 ? layout.root : layout.node(level - 1, i ~/ SimulationPlan.branching[level]);
        final child = layout.node(level, i);
        final mid = (parent.dy + child.dy) / 2;
        canvas.drawPath(
          Path()
            ..moveTo(parent.dx, parent.dy)
            ..lineTo(parent.dx, mid)
            ..lineTo(child.dx, mid)
            ..lineTo(child.dx, child.dy),
          faint,
        );
        _node(canvas, child, 2.5, dots);
      }
    }

    // Failed courses: grow, fail, stay behind in red (grey for Samaritan).
    final failedColor = samaritan ? SamaritanColors.ink.withValues(alpha: 0.35) : MachineColors.relevant.withValues(alpha: 0.65);
    for (var k = 0; k < SimulationPlan.failedRuns; k++) {
      final start = _Timeline.runStart(k);
      if (t < start) break;
      final run = plan.runs[k];
      final p = ((t - start) / _Timeline.runs[k]).clamp(0.0, 1.0);
      final leaf = layout.polyline(run.path).last;
      if (p >= 1) {
        _trail(canvas, layout.polyline(run.path), 1, failedColor, 1.5);
        _cross(canvas, leaf, samaritan ? SamaritanColors.red.withValues(alpha: 0.7) : failedColor);
        continue;
      }
      _trail(canvas, layout.polyline(run.path), (p / _Timeline.growing).clamp(0.0, 1.0), _ink.withValues(alpha: 0.95), 2);
      if (p >= _Timeline.growing) {
        final flash = ((p - _Timeline.growing) * 20).floor().isEven;
        _cross(canvas, leaf, flash ? (samaritan ? SamaritanColors.red : MachineColors.relevant) : failedColor);
      }
    }

    // Fast-forward: courses flicker past.
    if (t >= _Timeline.fastForwardStart && t < _Timeline.chosenStart) {
      final random = math.Random((t * 24).floor());
      for (var i = 0; i < 7; i++) {
        final path = [for (final b in SimulationPlan.branching) random.nextInt(b)];
        _trail(canvas, layout.polyline(path), 1, _ink.withValues(alpha: 0.3), 1.2);
      }
    }

    // The course it settles on.
    if (t >= _Timeline.chosenStart) {
      final p = ((t - _Timeline.chosenStart) / _Timeline.chosen).clamp(0.0, 1.0);
      final points = layout.polyline(plan.chosen.path);
      _trail(canvas, points, (p / _Timeline.growing).clamp(0.0, 1.0), accent, 2.6);
      if (p >= _Timeline.growing) {
        final leaf = points.last;
        _node(canvas, leaf, 5, Paint()..color = accent);
        // A ring keeps pulsing out of the answer.
        final pulse = ((t - _Timeline.chosenStart - _Timeline.chosen * _Timeline.growing) % 1.2) / 1.2;
        _node(
          canvas,
          leaf,
          5 + pulse * 16,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = accent.withValues(alpha: 1 - pulse),
        );
      }
    }

    // The subject at the root.
    _node(canvas, layout.root, 5, Paint()..color = samaritan ? SamaritanColors.red : _ink.withValues(alpha: appear));
  }

  /// Draws [points] up to [fraction] of their length.
  void _trail(Canvas canvas, List<Offset> points, double fraction, Color color, double width) {
    if (fraction <= 0) return;
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += (points[i] - points[i - 1]).distance;
    }
    var left = total * fraction;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    var end = points.first;
    for (var i = 1; i < points.length && left > 0; i++) {
      final segment = points[i] - points[i - 1];
      final length = segment.distance;
      end = length <= left ? points[i] : points[i - 1] + segment * (left / length);
      path.lineTo(end.dx, end.dy);
      left -= length;
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.miter
        ..color = color,
    );
    _node(canvas, end, width + 1.5, Paint()..color = color);
  }

  /// Squares for the Machine, dots for Samaritan.
  void _node(Canvas canvas, Offset at, double radius, Paint paint) {
    if (samaritan) {
      canvas.drawCircle(at, radius, paint);
    } else {
      canvas.drawRect(Rect.fromCircle(center: at, radius: radius), paint);
    }
  }

  void _cross(Canvas canvas, Offset at, Color color) {
    final paint = Paint()
      ..strokeWidth = 2
      ..color = color;
    const r = 5.0;
    canvas
      ..drawLine(at + const Offset(-r, -r), at + const Offset(r, r), paint)
      ..drawLine(at + const Offset(-r, r), at + const Offset(r, -r), paint);
  }

  @override
  bool shouldRepaint(_TreePainter old) => old.t != t || old.plan != plan || old.samaritan != samaritan;
}

/// Whether tapping [subject] should run a simulation instead of flagging.
bool simulatesOnTap(Subject subject) => isThreat(subject.displayDesignation);
