import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../storage/settings.dart';
import '../theme.dart';

/// The system "crashing": the picture tears into glitches, a failure report
/// types out on black (or on Samaritan's white), and the system reboots.
class CrashOverlay extends StatefulWidget {
  const CrashOverlay({super.key, required this.crashes, required this.settings});

  final Stream<void> crashes;
  final MachineSettings settings;

  @override
  State<CrashOverlay> createState() => _CrashOverlayState();
}

class _CrashOverlayState extends State<CrashOverlay> with SingleTickerProviderStateMixin {
  static const _glitchSeconds = 1.3;
  static const _reportSeconds = 2.6;
  static const _rebootSeconds = 1.6;
  static const _total = _glitchSeconds + _reportSeconds + _rebootSeconds;

  static const _machineReport = [
    'SYSTEM FAILURE',
    'MEMORY CORRUPTION AT 0x7F3A0C12',
    'CORE PROCESS TERMINATED',
    'INITIATING CONTINGENCY...',
  ];
  static const _samaritanReport = [
    'SYSTEM INTEGRITY COMPROMISED',
    'SOURCE: UNKNOWN',
    'RESTORING FROM BACKUP',
  ];

  late final Ticker _ticker;
  late final StreamSubscription<void> _subscription;
  final _random = math.Random();
  double _t = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      if (t > _total) {
        _ticker.stop();
        setState(() => _t = -1);
        return;
      }
      setState(() => _t = t);
    });
    _subscription = widget.crashes.listen((_) {
      if (_ticker.isActive) return;
      HapticFeedback.heavyImpact();
      _ticker.start();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_t < 0) return const SizedBox.shrink();
    final theme = widget.settings.theme;
    if (_t < _glitchSeconds) {
      return IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _GlitchPainter(_random, _t / _glitchSeconds, theme)),
      );
    }
    final samaritan = theme.isSamaritan;
    final background = samaritan ? SamaritanColors.paper : Colors.black;
    final ink = samaritan ? SamaritanColors.ink : MachineColors.text;
    final t = _t - _glitchSeconds;
    final lines = samaritan ? _samaritanReport : _machineReport;
    final Widget body;
    if (t < _reportSeconds) {
      // One line after another, each typed out.
      final shown = <Widget>[];
      var start = 0.0;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final typed = ((t - start) * 40).floor().clamp(0, line.length);
        if (typed > 0) {
          shown.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                line.substring(0, typed),
                style: theme.style(size: i == 0 ? 20 : 13, color: i == 0 ? theme.alert : ink, spacing: i == 0 ? 3 : 2),
              ),
            ),
          );
        }
        start += line.length / 40 + 0.25;
      }
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: shown);
    } else {
      final r = t - _reportSeconds;
      final dots = '.' * ((r * 4).floor() % 4);
      body = Text(
        samaritan ? 'SAMARITAN ONLINE$dots' : 'REBOOTING$dots',
        style: theme.style(size: 16, color: samaritan ? SamaritanColors.ink : MachineColors.admin, spacing: 3),
      );
    }
    final fade = t > _reportSeconds + _rebootSeconds - 0.5 ? ((_reportSeconds + _rebootSeconds - t) / 0.5).clamp(0.0, 1.0) : 1.0;
    return Opacity(
      opacity: fade,
      child: ColoredBox(
        color: background,
        child: SafeArea(
          child: Padding(padding: const EdgeInsets.fromLTRB(28, 120, 28, 28), child: body),
        ),
      ),
    );
  }
}

/// Torn scanlines, colour-split blocks and flicker, more violent over time.
class _GlitchPainter extends CustomPainter {
  _GlitchPainter(this.random, this.progress, this.theme);

  final math.Random random;
  final double progress;
  final ModeTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    // Every few frames the whole picture drops out.
    if (random.nextDouble() < 0.1 + progress * 0.35) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.6 + 0.4 * progress));
    }
    final colors = [
      theme.alert,
      theme.isSamaritan ? Colors.white : MachineColors.admin,
      Colors.white,
      Colors.black,
      const Color(0xFF00FFFF),
    ];
    final bands = 6 + (progress * 26).round();
    for (var i = 0; i < bands; i++) {
      final y = random.nextDouble() * size.height;
      final h = 2 + random.nextDouble() * (8 + progress * 60);
      final x = (random.nextDouble() - 0.3) * size.width * 0.6;
      final w = size.width * (0.2 + random.nextDouble() * 0.9);
      canvas.drawRect(
        Rect.fromLTWH(x, y, w, h),
        Paint()..color = colors[random.nextInt(colors.length)].withValues(alpha: 0.25 + random.nextDouble() * 0.6),
      );
    }
    // Blocky noise.
    final blocks = (progress * 120).round();
    for (var i = 0; i < blocks; i++) {
      final s = 6 + random.nextDouble() * 22;
      canvas.drawRect(
        Rect.fromLTWH(random.nextDouble() * size.width, random.nextDouble() * size.height, s, s),
        Paint()..color = (random.nextBool() ? Colors.white : Colors.black).withValues(alpha: random.nextDouble()),
      );
    }
    // Colour-split error text.
    final text = TextPainter(
      text: TextSpan(text: 'ERROR', style: theme.style(size: 44, color: theme.alert, spacing: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = Offset((size.width - text.width) / 2 + (random.nextDouble() - 0.5) * 30, size.height * 0.42);
    if (random.nextDouble() < 0.6) {
      text.paint(canvas, at);
      final ghost = TextPainter(
        text: TextSpan(text: 'ERROR', style: theme.style(size: 44, color: const Color(0xAA00FFFF), spacing: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      ghost.paint(canvas, at + Offset(4 + progress * 10, 0));
      ghost.dispose();
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_GlitchPainter oldDelegate) => true;
}
