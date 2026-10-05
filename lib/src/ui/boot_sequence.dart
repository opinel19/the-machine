import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../machine/machine_controller.dart';
import '../storage/settings.dart';
import '../theme.dart';
import 'hud.dart';

/// Start-up screen, replayed whenever the system switches: the Machine types
/// out its systems coming online on black; Samaritan asks for commands on
/// white. Tap to skip once everything is up.
class BootSequence extends StatefulWidget {
  const BootSequence({super.key, required this.controller});

  final MachineController controller;

  @override
  State<BootSequence> createState() => _BootSequenceState();
}

class _Step {
  const _Step(this.name, this.status, {this.failed = false});

  final String name;

  /// Null while the step is still in progress.
  final String? status;
  final bool failed;
}

class _BootSequenceState extends State<BootSequence> with SingleTickerProviderStateMixin {
  static const _typeRate = 70.0; // characters per second
  static const _firstLineAt = 0.9;
  static const _lineGap = 0.42;
  static const _lineLength = 26;
  static const _holdSeconds = 0.5;
  static const _fadeSeconds = 0.45;

  /// Samaritan's phrases and how long each stays up.
  static const _samaritanPhrases = [
    ('SAMARITAN', 1.1),
    ('CALCULATING RESPONSE', 1.3),
    ('WHAT ARE YOUR COMMANDS?', 1.4),
  ];

  late final Ticker _ticker;
  late MachineMode _mode;
  bool _firstBoot = true;
  double _t = 0;
  double? _readyAt;
  bool _gone = false;

  MachineSettings get _settings => widget.controller.settings;

  @override
  void initState() {
    super.initState();
    _mode = _settings.mode;
    _settings.addListener(_onSettings);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _ticker.dispose();
    super.dispose();
  }

  void _onSettings() {
    final mode = _settings.mode;
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      // Stored settings arrive just after launch; that is not a switch.
      _firstBoot = _firstBoot && !widget.controller.storageLoaded;
      _t = 0;
      _readyAt = null;
      _gone = false;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  List<_Step> _steps() {
    final c = widget.controller;
    final admins = c.identities.admins.length;
    return [
      const _Step('CORE SYSTEMS', 'ONLINE'),
      _Step(
        'SURVEILLANCE FEED',
        c.cameraError != null
            ? 'FAILED'
            : c.camera.value != null
            ? 'ONLINE'
            : null,
        failed: c.cameraError != null,
      ),
      _Step(
        'FACIAL RECOGNITION',
        switch (c.recognitionOnline) {
          null => null,
          true => 'ONLINE',
          false => 'OFFLINE',
        },
        failed: c.recognitionOnline == false,
      ),
      _Step('ADMIN PROFILES', !c.storageLoaded ? null : (admins == 0 ? 'NONE' : '${admins.toString().padLeft(2, '0')} FOUND')),
    ];
  }

  double _lineStart(int index) => _firstLineAt + index * _lineGap;

  bool get _systemsUp =>
      widget.controller.cameraError == null && _steps().every((s) => s.status != null);

  /// Seconds until the current sequence has said everything.
  double get _scriptLength {
    if (_mode == MachineMode.samaritan) {
      return _samaritanPhrases.fold(0.0, (sum, p) => sum + p.$2);
    }
    return _firstBoot ? _lineStart(3) + _lineLength / _typeRate : 2.0;
  }

  void _tick(Duration elapsed) {
    _t = elapsed.inMicroseconds / 1e6;
    if (_readyAt == null && _t >= _scriptLength && _systemsUp) _readyAt = _t;
    final ready = _readyAt;
    if (ready != null && _t > ready + _holdSeconds + _fadeSeconds) {
      _ticker.stop();
      setState(() => _gone = true);
      return;
    }
    setState(() {});
  }

  void _skip() {
    if (_readyAt == null && _systemsUp) _readyAt = _t - _holdSeconds;
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final ready = _readyAt;
    final opacity = ready == null ? 1.0 : (1 - (_t - ready - _holdSeconds) / _fadeSeconds).clamp(0.0, 1.0);
    final samaritan = _mode == MachineMode.samaritan;
    return IgnorePointer(
      ignoring: ready != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Opacity(
          opacity: opacity,
          child: ColoredBox(
            color: samaritan ? SamaritanColors.paper : Colors.black,
            child: SafeArea(child: samaritan ? _samaritan() : _machine()),
          ),
        ),
      ),
    );
  }

  Widget _machine() {
    final theme = ModeTheme.machine;
    final error = widget.controller.cameraError;
    final headline = _firstBoot ? 'YOU ARE BEING WATCHED.' : 'CAN YOU HEAR ME?';
    final typed = headline.substring(0, (_t * (_firstBoot ? 28 : 20)).floor().clamp(0, headline.length));
    final steps = _steps();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_firstBoot) ...[
            Text('THE MACHINE', style: theme.style(size: 11, color: theme.accent, spacing: 4)),
            const SizedBox(height: 10),
          ],
          Text(typed, style: theme.style(size: 18, spacing: 2.5)),
          const SizedBox(height: 28),
          if (_firstBoot)
            for (var i = 0; i < steps.length; i++) _line(steps[i], i),
          if (error != null) ...[
            const SizedBox(height: 24),
            Text(error, style: theme.style(size: 12, color: MachineColors.relevant)),
          ],
        ],
      ),
    );
  }

  Widget _line(_Step step, int index) {
    const height = 22.0;
    final theme = ModeTheme.machine;
    final start = _lineStart(index);
    if (_t < start) return const SizedBox(height: height);
    final lead = '> ${step.name} '.padRight(_lineLength, '.');
    final typed = ((_t - start) * _typeRate).floor().clamp(0, lead.length);
    final String status;
    if (typed < lead.length) {
      status = '';
    } else {
      status = step.status ?? const ['|', '/', '-', r'\'][(_t * 10).floor() % 4];
    }
    final statusColor = step.failed
        ? MachineColors.relevant
        : step.status == null
        ? MachineColors.dim
        : MachineColors.text;
    return SizedBox(
      height: height,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: lead.substring(0, typed), style: theme.style(size: 12, color: theme.dim)),
            TextSpan(text: ' $status', style: theme.style(size: 12, color: statusColor)),
          ],
        ),
      ),
    );
  }

  Widget _samaritan() {
    final theme = ModeTheme.samaritan;
    // Which phrase is up, and for how long.
    var start = 0.0;
    var index = 0;
    for (; index < _samaritanPhrases.length - 1; index++) {
      if (_t < start + _samaritanPhrases[index].$2) break;
      start += _samaritanPhrases[index].$2;
    }
    final (phrase, _) = _samaritanPhrases[index];
    final words = phrase.split(' ');
    final shownWords = ((_t - start) / 0.18).floor() + 1;
    final title = index == 0;
    final error = widget.controller.cameraError;
    final triangleOn = (_t * 2.5).floor().isEven;
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    words.take(shownWords.clamp(1, words.length)).join(' '),
                    textAlign: TextAlign.center,
                    style: theme.style(
                      size: title ? 30 : 19,
                      color: SamaritanColors.ink,
                      spacing: title ? 12 : 5,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!title) ...[
                  const SizedBox(width: 12),
                  Opacity(opacity: triangleOn ? 1 : 0, child: const SamaritanTriangle(size: 14)),
                ],
              ],
            ),
          ),
        ),
        if (error != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: theme.style(size: 12, color: SamaritanColors.red),
            ),
          ),
      ],
    );
  }
}
