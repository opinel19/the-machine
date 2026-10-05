import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../machine/machine_controller.dart';
import '../vision/image_codec.dart';
import 'box_painter.dart';

/// When the camera switches, the old picture breaks up into blocks and the
/// new one resolves out of them, like the show's cuts between feeds.
class PixelTransition extends StatefulWidget {
  const PixelTransition({super.key, required this.controller});

  final MachineController controller;

  @override
  State<PixelTransition> createState() => _PixelTransitionState();
}

enum _Phase { idle, breaking, waiting, resolving }

class _PixelTransitionState extends State<PixelTransition> with SingleTickerProviderStateMixin {
  /// Block columns across the screen, from fine to coarse.
  static const _widths = [48, 24, 12, 6];
  static const _stepSeconds = 0.08;

  late final Ticker _ticker;
  final _images = <ui.Image>[];
  _Phase _phase = _Phase.idle;
  double _t = 0;
  Duration _last = Duration.zero;
  CameraController? _camera;

  /// Only the latest capture may replace the images.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _camera = widget.controller.camera.value;
    widget.controller.camera.addListener(_onCamera);
    widget.controller.addListener(_onFrame);
  }

  @override
  void dispose() {
    widget.controller.camera.removeListener(_onCamera);
    widget.controller.removeListener(_onFrame);
    _ticker.dispose();
    _clearImages();
    super.dispose();
  }

  void _clearImages() {
    for (final image in _images) {
      image.dispose();
    }
    _images.clear();
  }

  Future<void> _capture() async {
    final frame = widget.controller.lastFrame;
    if (frame == null) return;
    final generation = ++_generation;
    final size = frame.size;
    final images = <ui.Image>[];
    for (final w in _widths) {
      final h = (w * size.height / size.width).round();
      images.add(await imageFromPixels(frame.regionRgba(Offset.zero & size, w, h), w, h));
    }
    if (!mounted || generation != _generation) {
      for (final i in images) {
        i.dispose();
      }
      return;
    }
    _clearImages();
    _images.addAll(images);
  }

  void _onCamera() {
    final camera = widget.controller.camera.value;
    final previous = _camera;
    _camera = camera;
    if (previous != null && camera == null && _phase == _Phase.idle) {
      _phase = _Phase.breaking;
      _t = 0;
      _capture();
      _start();
    }
  }

  /// Once the new camera has delivered a frame, resolve into it.
  void _onFrame() {
    if (_phase != _Phase.waiting && _phase != _Phase.breaking) return;
    if (widget.controller.camera.value == null || widget.controller.lastFrame == null) return;
    _phase = _Phase.resolving;
    _t = 0;
    _capture();
    _start();
  }

  void _start() {
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _t += dt;
    if (_phase == _Phase.breaking && _t > _widths.length * _stepSeconds) _phase = _Phase.waiting;
    if (_phase == _Phase.resolving && _t > _widths.length * _stepSeconds + 0.2) {
      _phase = _Phase.idle;
      _ticker.stop();
      _clearImages();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.idle || _images.isEmpty) return const SizedBox.shrink();
    final step = (_t / _stepSeconds).floor().clamp(0, _widths.length - 1);
    // Breaking: fine to coarse; resolving: coarse to fine, then fade.
    final index = _phase == _Phase.resolving ? _widths.length - 1 - step : step;
    final overrun = _t - _widths.length * _stepSeconds;
    final opacity = _phase == _Phase.resolving && overrun > 0 ? (1 - overrun / 0.2).clamp(0.0, 1.0) : 1.0;
    final image = _images[index.clamp(0, _images.length - 1)];
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: _CoverBlocksPainter(image, opacity)),
    );
  }
}

class _CoverBlocksPainter extends CustomPainter {
  const _CoverBlocksPainter(this.image, this.opacity);

  final ui.Image image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Size(image.width.toDouble(), image.height.toDouble());
    final mapping = FrameMapping(frame, size);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: opacity));
    paintBlocks(canvas, image, mapping.rect(Offset.zero & frame), opacity: opacity);
  }

  @override
  bool shouldRepaint(_CoverBlocksPainter old) => old.image != image || old.opacity != opacity;
}
