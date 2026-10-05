import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../machine/designation.dart';
import '../theme.dart';

/// Red pulses around the edges of the screen when a threat shows up.
class AlertFlash extends StatefulWidget {
  const AlertFlash({super.key, required this.alerts});

  final Stream<Designation> alerts;

  @override
  State<AlertFlash> createState() => _AlertFlashState();
}

class _AlertFlashState extends State<AlertFlash> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final StreamSubscription<Designation> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.alerts.listen((_) => _pulse.forward(from: 0));
  }

  @override
  void dispose() {
    _subscription.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          if (t == 0 || t == 1) return const SizedBox.shrink();
          // Two beats that fade out.
          final strength = (1 - t) * (0.5 + 0.5 * math.cos(t * math.pi * 4)).abs();
          return CustomPaint(size: Size.infinite, painter: _EdgeGlowPainter(strength));
        },
      ),
    );
  }
}

class _EdgeGlowPainter extends CustomPainter {
  const _EdgeGlowPainter(this.strength);

  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [
            MachineColors.relevant.withValues(alpha: 0),
            MachineColors.relevant.withValues(alpha: 0.55 * strength),
          ],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = MachineColors.relevant.withValues(alpha: 0.8 * strength),
    );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) => old.strength != strength;
}
