import 'package:flutter/material.dart';

import '../machine/events.dart';
import '../theme.dart';

/// The last few things the Machine noticed, fading out after a while.
class EventLogView extends StatelessWidget {
  const EventLogView({super.key, required this.log, required this.theme});

  static const _visible = 5;
  static const _lifetime = Duration(seconds: 25);

  final EventLog log;
  final ModeTheme theme;

  Color _color(EventKind kind) => switch (kind) {
    EventKind.admin => theme.accent,
    EventKind.alert => theme.alert,
    EventKind.number => theme.isSamaritan ? theme.text : MachineColors.admin,
    EventKind.info || EventKind.system => theme.text,
  };

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final events = log.events;
    final recent = events.sublist((events.length - _visible).clamp(0, events.length));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final event in recent)
            Builder(
              builder: (context) {
                final age = now.difference(event.time);
                final opacity = (1 - age.inMilliseconds / _lifetime.inMilliseconds).clamp(0.0, 1.0);
                if (opacity == 0) return const SizedBox.shrink();
                final t = event.time;
                return Opacity(
                  opacity: 0.35 + 0.65 * opacity,
                  child: Text(
                    '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  ${event.text}',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.style(size: 9.5, color: _color(event.kind), spacing: theme.isSamaritan ? 1.5 : 1),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
