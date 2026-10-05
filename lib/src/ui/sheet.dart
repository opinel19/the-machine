import 'package:flutter/material.dart';

import '../theme.dart';

/// A bottom sheet in the current system's style: black with the Machine,
/// white paper with Samaritan.
Future<T?> showMachineSheet<T>(
  BuildContext context, {
  required ModeTheme theme,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: theme.panel,
    shape: const RoundedRectangleBorder(),
    isScrollControlled: true,
    builder: (context) => Theme(
      data: theme.isSamaritan ? samaritanTheme() : machineTheme(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key, required this.theme});

  final String text;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (theme.isSamaritan) ...[
          CustomPaint(size: const Size(12, 10), painter: _Triangle()),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(text, style: theme.panelStyle(size: 14, color: theme.accent, spacing: theme.spacing * 1.6)),
        ),
      ],
    );
  }
}

class SheetSection extends StatelessWidget {
  const SheetSection(this.text, {super.key, required this.theme});

  final String text;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Text(text, style: theme.panelStyle(size: 10, color: theme.panelDim, spacing: theme.spacing * 1.4)),
    );
  }
}

class _Triangle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = SamaritanColors.red,
  );

  @override
  bool shouldRepaint(_Triangle old) => false;
}
