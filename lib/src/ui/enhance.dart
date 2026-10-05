import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../machine/machine_controller.dart';
import '../machine/subject.dart';
import '../theme.dart';
import '../vision/image_codec.dart';
import 'box_painter.dart';

/// Zooming in on one subject, as in the show's "enhance" shots. The camera
/// feed and the overlay both apply [zoom] and [pan].
class EnhanceState extends ChangeNotifier {
  static const _inSeconds = 0.6;
  static const _outSeconds = 0.35;

  int? subjectId;
  double _progress = 0;
  bool _closing = false;
  double _lostSeconds = 0;
  Rect? _focus;

  double zoom = 1;
  Offset pan = Offset.zero;

  bool get active => subjectId != null;

  /// 0 = normal view, 1 = fully zoomed in.
  double get progress => _progress;

  bool get settled => active && !_closing && _progress >= 1;

  void start(int id) {
    subjectId = id;
    _closing = false;
    _lostSeconds = 0;
    notifyListeners();
  }

  void stop() {
    if (active) _closing = true;
  }

  /// Advances the animation; called every frame by the overlay.
  void tick(double dt, Subject? subject, Size? frame, Size view) {
    if (!active || frame == null) return;
    if (subject == null) {
      _lostSeconds += dt;
      if (_lostSeconds > 1) _closing = true;
    } else {
      _lostSeconds = 0;
      final target = headSquare(subject.box);
      _focus = _focus == null ? target : Rect.lerp(_focus, target, 1 - math.exp(-dt * 10));
    }
    _progress = (_progress + (_closing ? -dt / _outSeconds : dt / _inSeconds)).clamp(0.0, 1.0);
    if (_closing && _progress == 0) {
      subjectId = null;
      _focus = null;
      zoom = 1;
      pan = Offset.zero;
      notifyListeners();
      return;
    }
    final focus = _focus;
    if (focus == null) return;
    final square = FrameMapping(frame, view).rect(focus);
    final targetZoom = (0.55 * view.shortestSide / square.width).clamp(1.0, 8.0);
    final t = Curves.easeInOutCubic.transform(_progress);
    zoom = 1 + (targetZoom - 1) * t;
    final destination = Offset.lerp(square.center, Offset(view.width / 2, view.height * 0.4), t)!;
    pan = destination - square.center * zoom;
    notifyListeners();
  }

  /// The zoomed head square of the subject on screen.
  Rect? focusOnScreen(Size frame, Size view) {
    final focus = _focus;
    return focus == null ? null : FrameMapping(frame, view, zoom: zoom, pan: pan).rect(focus);
  }

  Rect? get focusInFrame => _focus;
}

/// Draws the enhance effect: the zoomed face resolves from coarse blocks to
/// live video, with the subject's file alongside.
class EnhanceOverlay extends StatefulWidget {
  const EnhanceOverlay({super.key, required this.controller, required this.enhance});

  final MachineController controller;
  final EnhanceState enhance;

  @override
  State<EnhanceOverlay> createState() => _EnhanceOverlayState();
}

class _EnhanceOverlayState extends State<EnhanceOverlay> with SingleTickerProviderStateMixin {
  /// Block resolutions the face passes through before going live.
  static const _steps = [6, 9, 14, 21, 32, 48, 72];
  static const _stepSeconds = 0.11;
  static const _fadeSeconds = 0.3;

  late final Ticker _ticker;
  double _settledFor = -1;
  int _requested = -1;
  ui.Image? _blocks;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blocks?.dispose();
    super.dispose();
  }

  Duration _last = Duration.zero;

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final enhance = widget.enhance;
    if (!enhance.settled) {
      if (_settledFor >= 0) {
        setState(() {
          _settledFor = -1;
          _requested = -1;
          _blocks?.dispose();
          _blocks = null;
        });
      }
      return;
    }
    _settledFor = math.max(_settledFor, 0) + dt;
    final step = (_settledFor / _stepSeconds).floor();
    if (step < _steps.length && step != _requested) {
      _requested = step;
      _loadBlocks(_steps[step]);
    }
    setState(() {});
  }

  Future<void> _loadBlocks(int size) async {
    final frame = widget.controller.lastFrame;
    final focus = widget.enhance.focusInFrame;
    if (frame == null || focus == null) return;
    final image = await imageFromPixels(frame.regionRgba(focus, size, size), size, size);
    if (!mounted || !widget.enhance.settled) {
      image.dispose();
      return;
    }
    setState(() {
      _blocks?.dispose();
      _blocks = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enhance = widget.enhance;
    if (!enhance.active) return const SizedBox.shrink();
    final controller = widget.controller;
    final theme = ModeTheme.of(controller.settings.mode);
    final subject = controller.subjects.where((s) => s.id == enhance.subjectId).firstOrNull;
    final resolving = _settledFor >= 0 && _settledFor < _steps.length * _stepSeconds;
    final fade = _settledFor < 0
        ? 0.0
        : resolving
        ? 1.0
        : (1 - (_settledFor - _steps.length * _stepSeconds) / _fadeSeconds).clamp(0.0, 1.0);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final view = constraints.biggest;
          final frame = controller.frameSize;
          final square = frame == null ? null : enhance.focusOnScreen(frame, view);
          return Stack(
            children: [
              if (square != null && _blocks != null && fade > 0)
                Positioned.fill(
                  child: CustomPaint(painter: _BlocksPainter(_blocks!, square, fade)),
                ),
              if (square != null && resolving)
                Positioned(
                  left: square.left,
                  top: square.top - 22,
                  child: Text(
                    theme.isSamaritan ? 'RESOLVING' : 'ENHANCING...',
                    style: theme.style(size: 12, color: theme.accent),
                  ),
                ),
              if (subject != null && enhance.progress > 0.5)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.paddingOf(context).bottom + 96,
                  child: Opacity(
                    opacity: ((enhance.progress - 0.5) * 2).clamp(0.0, 1.0),
                    child: _Dossier(subject: subject, controller: controller, theme: theme),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BlocksPainter extends CustomPainter {
  _BlocksPainter(this.image, this.square, this.opacity);

  final ui.Image image;
  final Rect square;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) => paintBlocks(canvas, image, square, opacity: opacity);

  @override
  bool shouldRepaint(_BlocksPainter old) => old.image != image || old.square != square || old.opacity != opacity;
}

/// The subject's file, shown while zoomed in.
class _Dossier extends StatelessWidget {
  const _Dossier({required this.subject, required this.controller, required this.theme});

  final Subject subject;
  final MachineController controller;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    final mode = controller.settings.mode;
    final designation = subject.displayDesignation;
    final name = subject.identity?.name;
    final rows = <(String, String)>[
      ('DESIGNATION', designation.label(mode)),
      if (name != null) ('IDENTITY', name),
      if (subject.identity != null) ('MATCH', '${(subject.similarity * 100).clamp(0, 100).toStringAsFixed(0)}%'),
      ('DISTANCE', '${subject.distanceMeters(controller.focalPixels).toStringAsFixed(1)} M'),
      if (subject.issuedNumber != null) ('SSN', subject.issuedNumber!),
    ];
    final samaritan = theme.isSamaritan;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.panel,
        border: Border(left: BorderSide(color: theme.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            samaritan ? 'SUBJECT ANALYSIS // ${subject.code}' : 'ENHANCE // ${subject.code}',
            style: theme.panelStyle(size: 12, color: theme.accent),
          ),
          const SizedBox(height: 6),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(width: 120, child: Text(label, style: theme.panelStyle(size: 11, color: theme.panelDim))),
                  Expanded(child: Text(value, style: theme.panelStyle(size: 12))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
