import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../storage/settings.dart';
import '../theme.dart';
import 'hud.dart';

/// Shows the latest status message for a moment: typed out on the Machine's
/// dark panel, or word by word on Samaritan's white bar.
class MessageBanner extends StatefulWidget {
  const MessageBanner({super.key, required this.messages, required this.settings});

  final Stream<String> messages;
  final MachineSettings settings;

  @override
  State<MessageBanner> createState() => _MessageBannerState();
}

class _MessageBannerState extends State<MessageBanner> with SingleTickerProviderStateMixin {
  static const _visibleFor = Duration(milliseconds: 2600);

  late final Ticker _ticker;
  late final StreamSubscription<String> _subscription;
  String? _message;
  Duration _shownAt = Duration.zero;
  Duration _now = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _subscription = widget.messages.listen((message) {
      setState(() {
        _message = message;
        _shownAt = _now;
      });
      if (!_ticker.isActive) {
        _now = Duration.zero;
        _shownAt = Duration.zero;
        _ticker.start();
      }
    });
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    if (_now - _shownAt > _visibleFor) {
      _ticker.stop();
      setState(() => _message = null);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    if (message == null) return const SizedBox.shrink();
    final theme = widget.settings.theme;
    final seconds = (_now - _shownAt).inMicroseconds / 1e6;
    final String shown;
    if (theme.isSamaritan) {
      final words = message.split(' ');
      shown = words.take((1 + seconds * 6).floor().clamp(1, words.length)).join(' ');
    } else {
      shown = '> ${message.substring(0, (seconds * 60).floor().clamp(0, message.length))}';
    }
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 200,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.panel,
              border: theme.isSamaritan ? null : Border(left: BorderSide(color: theme.accent, width: 3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(shown, style: theme.panelStyle(size: 12))),
                if (theme.isSamaritan) ...[const SizedBox(width: 10), const SamaritanTriangle(size: 10)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
