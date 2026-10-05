import 'package:flutter/material.dart';

import '../machine/enrollment.dart';
import '../machine/machine_controller.dart';
import '../theme.dart';
import 'hud.dart';

/// Guidance and progress while the Machine scans an admin's face.
class EnrollmentView extends StatelessWidget {
  const EnrollmentView({super.key, required this.controller});

  final MachineController controller;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final enrollment = controller.enrollment;
        if (enrollment == null) return const SizedBox.shrink();
        final theme = controller.settings.theme;
        final finished = enrollment.finished;
        final title = finished
            ? 'ADMIN PROFILE STORED'
            : enrollment.extending != null
            ? 'ADDING A LOOK'
            : enrollment.replacing != null
            ? 'ADMIN RE-SCAN'
            : theme.isSamaritan
            ? 'IDENTITY REGISTRATION'
            : 'NEW ADMIN';
        return Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Color(0x4D000000)))),
            Positioned(
              left: 20,
              right: 20,
              top: padding.top + 70,
              child: IgnorePointer(
                child: Column(
                  children: [
                    Text(title, style: theme.style(size: 18, color: theme.accent, spacing: theme.spacing * 2)),
                    const SizedBox(height: 4),
                    Text('// ${enrollment.name}', style: theme.style(size: 13, color: theme.accent)),
                    const SizedBox(height: 10),
                    Text(
                      finished ? enrollment.result ?? '' : enrollment.hint.text,
                      textAlign: TextAlign.center,
                      style: theme.style(size: 13),
                    ),
                    const SizedBox(height: 16),
                    _Segments(
                      filled: finished ? Enrollment.sampleCount : enrollment.samples.length,
                      color: theme.accent,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${enrollment.samples.length.toString().padLeft(2, '0')} / ${Enrollment.sampleCount}',
                      style: theme.style(size: 11, color: theme.dim),
                    ),
                  ],
                ),
              ),
            ),
            if (!finished)
              Positioned(
                left: 0,
                right: 0,
                bottom: padding.bottom + 18,
                child: Center(
                  child: MachineButton(
                    theme: theme,
                    icon: Icons.close,
                    label: 'ABORT',
                    onTap: controller.cancelEnrollment,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.filled, required this.color});

  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < Enrollment.sampleCount; i++)
          Container(
            width: 12,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: i < filled ? color : const Color(0x40FFFFFF),
          ),
      ],
    );
  }
}
