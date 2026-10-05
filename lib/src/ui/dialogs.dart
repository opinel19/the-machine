import 'package:flutter/material.dart';

import '../theme.dart';

/// Asks for a name; returns null if cancelled.
Future<String?> askName(
  BuildContext context, {
  required ModeTheme theme,
  required String title,
  required String initial,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(theme: theme, title: title, initial: initial),
  );
}

/// Asks the user to confirm [action]; returns true if they did.
Future<bool> confirmAction(
  BuildContext context, {
  required ModeTheme theme,
  required String title,
  required String message,
  required String action,
  bool danger = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _MachineDialog(
      theme: theme,
      title: title,
      content: Text(message, style: theme.panelStyle(size: 12)),
      action: action,
      danger: danger,
      onAction: () => Navigator.pop(context, true),
    ),
  );
  return confirmed ?? false;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.theme, required this.title, required this.initial});

  final ModeTheme theme;
  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _text.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return _MachineDialog(
      theme: theme,
      title: widget.title,
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: 16,
        textCapitalization: TextCapitalization.characters,
        cursorColor: theme.accent,
        style: theme.panelStyle(size: 16, spacing: 2),
        decoration: InputDecoration(
          counterText: '',
          hintText: 'NAME',
          hintStyle: theme.panelStyle(size: 16, color: theme.panelDim, spacing: 2),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.panelDim)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.accent)),
        ),
        onSubmitted: (_) => _submit(),
      ),
      action: 'OK',
      onAction: _submit,
    );
  }
}

class _MachineDialog extends StatelessWidget {
  const _MachineDialog({
    required this.theme,
    required this.title,
    required this.content,
    required this.action,
    required this.onAction,
    this.danger = false,
  });

  final ModeTheme theme;
  final String title;
  final Widget content;
  final String action;
  final VoidCallback onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? theme.alert : theme.accent;
    return AlertDialog(
      backgroundColor: theme.isSamaritan ? SamaritanColors.paper : MachineColors.panel,
      shape: RoundedRectangleBorder(side: BorderSide(color: accent)),
      title: Text(title, style: theme.panelStyle(size: 15, color: accent, spacing: theme.spacing * 1.6)),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: theme.panelStyle(color: theme.panelDim)),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(action, style: theme.panelStyle(color: accent)),
        ),
      ],
    );
  }
}
