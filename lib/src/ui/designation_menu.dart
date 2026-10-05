import 'package:flutter/material.dart';

import '../machine/designation.dart';
import '../storage/settings.dart';
import '../theme.dart';
import 'box_painter.dart';
import 'sheet.dart';

/// Lets the user pick a designation for [subjectLabel]; returns null if
/// dismissed. [Designation.irrelevant] means "clear". [onSimulate] adds a
/// row that runs a simulation on the subject instead.
Future<Designation?> pickDesignation(
  BuildContext context, {
  required MachineSettings settings,
  required String subjectLabel,
  Designation? current,
  VoidCallback? onSimulate,
}) {
  final theme = settings.theme;
  return showMachineSheet<Designation>(
    context,
    theme: theme,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(theme.isSamaritan ? 'CLASSIFY $subjectLabel' : 'DESIGNATE $subjectLabel', theme: theme),
        const SizedBox(height: 8),
        if (onSimulate != null)
          InkWell(
            onTap: () {
              Navigator.pop(context);
              onSimulate();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Text(
                theme.isSamaritan ? '> PREDICTIVE ANALYSIS' : '> RUN SIMULATION',
                style: theme.panelStyle(size: 13, color: theme.accent),
              ),
            ),
          ),
        for (final designation in [...Designation.assignable, Designation.irrelevant])
          InkWell(
            onTap: () => Navigator.pop(context, designation),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: CustomPaint(painter: DesignationIcon(designation, settings.mode)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      designation == Designation.irrelevant
                          ? '${designation.label(settings.mode)} (CLEAR)'
                          : designation.label(settings.mode),
                      style: theme.panelStyle(
                        size: 13,
                        color: designation == current ? theme.accent : null,
                      ),
                    ),
                  ),
                  if (designation == current) Icon(Icons.check, size: 18, color: theme.accent),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

/// A small box (the Machine) or mark (Samaritan) for a designation.
class DesignationIcon extends CustomPainter {
  const DesignationIcon(this.designation, this.mode);

  final Designation designation;
  final MachineMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(3);
    if (mode == MachineMode.samaritan) {
      paintSamaritanMark(canvas, rect.center, rect.width * 0.36, SamaritanMark.of(designation));
    } else {
      canvas.drawRect(rect, Paint()..color = const Color(0x55000000));
      paintMachineBox(canvas, rect, BoxColors.of(designation), solidEdges: designation == Designation.threat);
    }
  }

  @override
  bool shouldRepaint(DesignationIcon old) => old.designation != designation || old.mode != mode;
}
