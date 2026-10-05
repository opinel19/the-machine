import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../platform/location_service.dart';
import '../theme.dart';
import 'event_log_view.dart';

/// Feed label, clock, event log, status readout and controls around the
/// camera view, in the current system's style.
class MachineHud extends StatelessWidget {
  const MachineHud({
    super.key,
    required this.controller,
    required this.onAdmin,
    required this.onSettings,
    required this.onCapture,
    required this.onTalk,
  });

  final MachineController controller;
  final VoidCallback onAdmin;
  final VoidCallback onSettings;
  final VoidCallback onCapture;
  final VoidCallback onTalk;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final settings = controller.settings;
        final theme = settings.theme;
        final busy = controller.enrollment != null || controller.verification != null;
        final buttons = [
          MachineButton(
            theme: theme,
            icon: Icons.cameraswitch_outlined,
            label: 'CAMERA',
            onTap: controller.canSwitchCamera ? controller.switchCamera : null,
          ),
          MachineButton(
            theme: theme,
            icon: Icons.admin_panel_settings_outlined,
            label: 'ADMIN',
            highlight: controller.storageLoaded && controller.identities.admins.isEmpty,
            onTap: onAdmin,
          ),
          if (!theme.isSamaritan)
            MachineButton(theme: theme, icon: Icons.dialpad, label: 'NUMBER', onTap: controller.issueNumber),
          MachineButton(
            theme: theme,
            icon: controller.recording ? Icons.stop_circle_outlined : Icons.camera_alt_outlined,
            label: controller.recording ? 'STOP' : 'CAPTURE',
            highlight: controller.recording,
            onTap: controller.recording ? controller.toggleRecording : onCapture,
            onLongPress: controller.toggleRecording,
          ),
          MachineButton(theme: theme, icon: Icons.tune, label: 'SYSTEM', onTap: onSettings),
        ];
        final logRight = landscape ? padding.right + 100 : 16.0;
        return Stack(
          children: [
            Positioned(
              left: padding.left + 16,
              top: padding.top + 6,
              // Tapping the system's name opens a conversation with it.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTalk,
                child: _FeedLabel(controller: controller, theme: theme),
              ),
            ),
            Positioned(
              right: logRight,
              top: padding.top + 6,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MachineClock(theme: theme),
                    if (settings.eventLog) ...[
                      const SizedBox(height: 10),
                      EventLogView(log: controller.events, theme: theme),
                    ],
                  ],
                ),
              ),
            ),
            if (!busy) ...[
              Positioned(
                left: padding.left + 16,
                right: landscape ? padding.right + 100 : 16,
                bottom: landscape ? padding.bottom + 12 : padding.bottom + 96,
                child: IgnorePointer(child: _StatusBlock(controller: controller, theme: theme)),
              ),
              if (landscape)
                Positioned(
                  right: padding.right + 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final b in buttons) Padding(padding: const EdgeInsets.all(3), child: b)],
                    ),
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: padding.bottom + 18,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [for (final b in buttons) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: b)],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _FeedLabel extends StatelessWidget {
  const _FeedLabel({required this.controller, required this.theme});

  final MachineController controller;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    final recording = controller.recording;
    String two(int n) => n.toString().padLeft(2, '0');
    final elapsed = controller.recordingElapsed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (theme.isSamaritan)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(size: const Size(12, 10), painter: _TrianglePainter(SamaritanColors.red)),
              const SizedBox(width: 8),
              Text('SAMARITAN', style: theme.style(size: 14, spacing: 6, weight: FontWeight.w600)),
            ],
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Blink(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: MachineColors.relevant, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 6),
              Text('LIVE', style: theme.style(size: 13, spacing: 2)),
            ],
          ),
        const SizedBox(height: 2),
        Text(
          controller.night ? '${controller.feed.label} // NIGHT' : controller.feed.label,
          style: theme.style(size: 11, color: controller.night ? theme.accent : theme.dim),
        ),
        if (controller.settings.location && controller.location.position != null) ...[
          const SizedBox(height: 4),
          Text(
            formatCoordinates(controller.location.position!.latitude, controller.location.position!.longitude),
            style: theme.style(size: 10, color: theme.dim, spacing: 1),
          ),
          if (controller.location.place != null)
            Text(controller.location.place!, style: theme.style(size: 10, color: theme.dim, spacing: 1)),
        ],
        if (recording) ...[
          const SizedBox(height: 6),
          Blink(
            period: const Duration(milliseconds: 1200),
            child: Text(
              '● REC ${two(elapsed.inMinutes)}:${two(elapsed.inSeconds % 60)}',
              style: theme.style(size: 12, color: theme.alert),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.controller, required this.theme});

  final MachineController controller;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    int inView(bool Function(Designation d) test) =>
        controller.subjects.where((s) => test(s.displayDesignation)).length;
    final identities = controller.identities;
    final admins = identities.admins.length;
    final flaggedTotal = identities.flagged.length;
    final rows = <(String, String, Color)>[];
    if (theme.isSamaritan) {
      final targets = inView((d) => d == Designation.admin || d == Designation.analogInterface || d == Designation.asset);
      final threats = inView((d) => d == Designation.relevant || d == Designation.threat);
      rows
        ..add(('TRACKING', two(controller.subjects.length), theme.text))
        ..add(('TARGETS', two(targets), targets > 0 ? theme.alert : theme.text))
        ..add(('DEVIANTS', two(inView((d) => d == Designation.perpetrator)), theme.text))
        ..add(('THREATS', two(threats), threats > 0 ? theme.alert : theme.text));
    } else {
      final flagged = inView((d) => Designation.assignable.contains(d));
      rows
        ..add(('SUBJECTS', two(controller.subjects.length), theme.text))
        ..add(
          admins == 0
              ? ('ADMIN', 'NO PROFILE', theme.dim)
              : ('ADMIN', '${two(controller.adminsInView)} / ${two(admins)}', controller.adminsInView > 0 ? theme.accent : theme.text),
        )
        ..add(('FLAGGED', '${two(flagged)} / ${two(flaggedTotal)}', flagged > 0 ? theme.alert : theme.text));
    }
    if (controller.settings.showScores) {
      rows.add(('PROCESSING', '${controller.processingFps.toStringAsFixed(0)} FPS', theme.text));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value, color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                SizedBox(width: 118, child: Text(label, style: theme.style(size: 12, color: theme.dim))),
                Text(value, style: theme.style(size: 12, color: color)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (controller.storageLoaded && admins == 0)
          Blink(
            child: Text('NO ADMIN PROFILE. TAP ADMIN TO ENROLL.', style: theme.style(size: 11, color: theme.accent)),
          )
        else if (controller.subjects.isNotEmpty)
          Text(
            'TAP: FLAG  ·  DOUBLE TAP: ENHANCE  ·  HOLD: DESIGNATE',
            style: theme.style(size: 9, color: theme.dim, spacing: 1),
          ),
      ],
    );
  }
}

/// A control in the current system's style.
class MachineButton extends StatelessWidget {
  const MachineButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    this.onTap,
    this.onLongPress,
    this.highlight = false,
  });

  final ModeTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? theme.dim
        : highlight
        ? theme.accent
        : theme.text;
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.heavyImpact();
              onLongPress!();
            },
      child: CustomPaint(
        painter: _ButtonFramePainter(color, samaritan: theme.isSamaritan),
        child: SizedBox(
          width: 66,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 21, color: color),
              const SizedBox(height: 5),
              Text(label, style: theme.style(size: 9, color: color, spacing: theme.isSamaritan ? 2 : 1.4)),
            ],
          ),
        ),
      ),
    );
    return highlight ? Blink(period: const Duration(milliseconds: 1400), child: button) : button;
  }
}

class _ButtonFramePainter extends CustomPainter {
  const _ButtonFramePainter(this.color, {required this.samaritan});

  final Color color;
  final bool samaritan;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(0x73000000));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = color;
    if (samaritan) {
      canvas.drawRect(r.deflate(0.5), line..strokeWidth = 1);
      return;
    }
    const arm = 9.0;
    final path = Path()
      ..moveTo(r.left, r.top + arm)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + arm, r.top)
      ..moveTo(r.right - arm, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + arm)
      ..moveTo(r.right, r.bottom - arm)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - arm, r.bottom)
      ..moveTo(r.left + arm, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - arm);
    canvas.drawPath(path, line..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_ButtonFramePainter old) => old.color != color || old.samaritan != samaritan;
}

/// Samaritan's red, upside-down triangle.
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// Samaritan's triangle as a widget.
class SamaritanTriangle extends StatelessWidget {
  const SamaritanTriangle({super.key, this.size = 12});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 0.86), painter: const _TrianglePainter(SamaritanColors.red));
}

/// Date and time down to the millisecond, like the show's surveillance feeds.
class MachineClock extends StatefulWidget {
  const MachineClock({super.key, required this.theme});

  final ModeTheme theme;

  @override
  State<MachineClock> createState() => _MachineClockState();
}

class _MachineClockState extends State<MachineClock> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final now = DateTime.now();
      if (now.difference(_now).inMilliseconds >= 33) setState(() => _now = now);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${_now.year}.${two(_now.month)}.${two(_now.day)}';
    final time = theme.isSamaritan
        ? '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}'
        : '${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}:${_now.millisecond.toString().padLeft(3, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(date, style: theme.style(size: 11, color: theme.dim)),
        const SizedBox(height: 2),
        Text(time, style: theme.style(size: theme.isSamaritan ? 16 : 14, spacing: theme.isSamaritan ? 3 : 1.2)),
      ],
    );
  }
}

/// Switches its child on and off on a fixed rhythm, like a status light.
class Blink extends StatefulWidget {
  const Blink({super.key, required this.child, this.period = const Duration(milliseconds: 1000)});

  final Widget child;
  final Duration period;

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.period)
    ..repeat();
  late final Animation<double> _opacity = _controller
      .drive(CurveTween(curve: const Threshold(0.6)))
      .drive(Tween(begin: 1.0, end: 0.2));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: widget.child);
}

/// CRT-style scanlines (the Machine only) and a vignette over the feed.
class FeedTexturePainter extends CustomPainter {
  const FeedTexturePainter({required this.scanlines});

  final bool scanlines;

  @override
  void paint(Canvas canvas, Size size) {
    if (scanlines) {
      final lines = Paint()..color = const Color(0x18000000);
      for (var y = 0.0; y < size.height; y += 3) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), lines);
      }
    }
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          radius: 1.2,
          colors: [Color(0x00000000), Color(0x8C000000)],
          stops: [0.45, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(FeedTexturePainter oldDelegate) => oldDelegate.scanlines != scanlines;
}
