import 'package:flutter/material.dart';

import '../machine/machine_controller.dart';
import '../theme.dart';
import 'hud.dart';

/// "Show me an admin" screen guarding settings and profiles while the admin
/// lock is on.
class VerificationView extends StatelessWidget {
  const VerificationView({super.key, required this.controller});

  final MachineController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final v = controller.verification;
        if (v == null) return const SizedBox.shrink();
        final theme = controller.settings.theme;
        final remaining = ((v.deadlineMs - controller.nowMs) / 10000).clamp(0.0, 1.0);
        final title = theme.isSamaritan ? 'IDENTITY VERIFICATION' : 'ADMIN VERIFICATION REQUIRED';
        return Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x66000000)))),
            Positioned(
              left: 24,
              right: 24,
              top: MediaQuery.paddingOf(context).top + 90,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: BoxDecoration(
                  color: theme.panel,
                  border: Border.all(color: v.denied ? theme.alert : theme.accent),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (theme.isSamaritan) ...[const SamaritanTriangle(), const SizedBox(width: 8)],
                        Expanded(
                          child: Text(
                            v.denied ? 'ACCESS DENIED' : title,
                            style: theme.panelStyle(size: 14, color: v.denied ? theme.alert : theme.accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      v.denied ? 'NO ADMIN RECOGNISED.' : 'LOOK AT THE CAMERA.',
                      style: theme.panelStyle(size: 12),
                    ),
                    const SizedBox(height: 10),
                    if (!v.denied)
                      LinearProgressIndicator(
                        value: remaining,
                        minHeight: 3,
                        color: theme.accent,
                        backgroundColor: theme.panelDim.withValues(alpha: 0.2),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: controller.cancelVerification,
                          child: Text('CANCEL', style: theme.panelStyle(color: theme.panelDim)),
                        ),
                        TextButton(
                          onPressed: controller.verifyWithPasscode,
                          child: Text('USE PASSCODE', style: theme.panelStyle(color: theme.accent)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
