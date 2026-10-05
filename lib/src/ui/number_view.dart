import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../machine/machine_controller.dart';
import '../theme.dart';

/// The Machine giving out a number: digits spin and lock one by one, then the
/// number stays up for a moment.
class NumberView extends StatefulWidget {
  const NumberView({super.key, required this.controller});

  final MachineController controller;

  @override
  State<NumberView> createState() => _NumberViewState();
}

class _NumberViewState extends State<NumberView> with SingleTickerProviderStateMixin {
  static const _showMs = 7500;
  static const _firstLockMs = 500;
  static const _lockStepMs = 140;

  late final Ticker _ticker;
  final _random = math.Random();
  IssuedNumber? _number;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _update());
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _ticker.dispose();
    super.dispose();
  }

  void _onController() {
    final issued = widget.controller.issuedNumber;
    if (issued != null && issued != _number) {
      _number = issued;
      if (!_ticker.isActive) _ticker.start();
    }
  }

  void _update() {
    final number = _number;
    if (number == null || widget.controller.nowMs - number.issuedMs > _showMs) {
      _ticker.stop();
      setState(() => _number = null);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final number = _number;
    if (number == null) return const SizedBox.shrink();
    final age = widget.controller.nowMs - number.issuedMs;
    var digitIndex = 0;
    final shown = StringBuffer();
    for (final c in number.ssn.split('')) {
      if (c == '-') {
        shown.write('-');
        continue;
      }
      final locked = age >= _firstLockMs + digitIndex * _lockStepMs;
      shown.write(locked ? c : _random.nextInt(10));
      digitIndex++;
    }
    final fade = ((_showMs - age) / 600).clamp(0.0, 1.0) * (age / 200).clamp(0.0, 1.0);
    final ringing = age < 4200 && (age ~/ 250).isEven;
    return IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: Align(
          alignment: const Alignment(0, -0.45),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: BoxDecoration(
              color: MachineColors.panel,
              border: Border.all(color: MachineColors.admin, width: 1.2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_in_talk, size: 16, color: ringing ? MachineColors.admin : MachineColors.dim),
                    const SizedBox(width: 8),
                    Text('INCOMING NUMBER', style: machineStyle(size: 12, color: MachineColors.admin, spacing: 3)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(shown.toString(), style: machineStyle(size: 34, spacing: 4, color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'PERSON OF INTEREST // ${number.subjectCode}',
                  style: machineStyle(size: 10, color: MachineColors.dim, spacing: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
