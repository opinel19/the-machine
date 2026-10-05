import 'package:flutter/material.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../storage/identity_store.dart';
import '../theme.dart';
import 'dialogs.dart';
import 'sheet.dart';

/// Lists the admin profiles; admins can be added, renamed, re-scanned and
/// deleted from here.
Future<void> showAdminSheet(BuildContext context, MachineController controller) {
  return showMachineSheet<void>(
    context,
    theme: controller.settings.theme,
    builder: (context) => _AdminSheet(controller: controller),
  );
}

/// Asks for a name, then starts scanning a new admin's face.
Future<void> enrollNewAdmin(BuildContext context, MachineController controller) async {
  final name = await askName(
    context,
    theme: controller.settings.theme,
    title: 'NEW ADMIN',
    initial: controller.identities.suggestAdminName(),
  );
  if (name != null) await controller.startEnrollment(name: name);
}

class _AdminSheet extends StatelessWidget {
  const _AdminSheet({required this.controller});

  final MachineController controller;

  Future<void> _add(BuildContext context) async {
    final name = await askName(
      context,
      theme: controller.settings.theme,
      title: 'NEW ADMIN',
      initial: controller.identities.suggestAdminName(),
    );
    if (name == null || !context.mounted) return;
    Navigator.pop(context);
    await controller.startEnrollment(name: name);
  }

  Future<void> _rename(BuildContext context, Identity admin) async {
    final name = await askName(context, theme: controller.settings.theme, title: 'RENAME ADMIN', initial: admin.name ?? '');
    if (name != null) await controller.renameIdentity(admin, name);
  }

  void _rescan(BuildContext context, Identity admin) {
    Navigator.pop(context);
    controller.startEnrollment(name: admin.name ?? '', replacing: admin);
  }

  void _extend(BuildContext context, Identity admin) {
    Navigator.pop(context);
    controller.startEnrollment(name: admin.name ?? '', extending: admin);
  }

  /// Everything else about one admin: extra looks, sensitivity, re-scan,
  /// delete.
  Future<void> _details(BuildContext context, Identity admin) {
    final sheetContext = context;
    return showMachineSheet<void>(
      context,
      theme: controller.settings.theme,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = controller.settings.theme;
          final current = controller.identities.admins.where((a) => a.id == admin.id).firstOrNull;
          if (current == null) return const SizedBox.shrink();
          final offset = current.thresholdOffset;
          final inView = controller.subjects.where((s) => identical(s.identity, current)).firstOrNull;
          void close(void Function() then) {
            Navigator.pop(context);
            if (sheetContext.mounted) then();
          }

          return Theme(
            data: theme.isSamaritan ? samaritanTheme() : machineTheme(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitle(current.displayName, theme: theme),
                const SizedBox(height: 6),
                Text(
                  '${current.embeddings.length} SCANNED + ${current.learned.length} LEARNED SAMPLES',
                  style: theme.panelStyle(size: 10, color: theme.panelDim),
                ),
                SheetSection('SENSITIVITY', theme: theme),
                Row(
                  children: [
                    Text('MATCH THRESHOLD', style: theme.panelStyle()),
                    const Spacer(),
                    Text(
                      '${(controller.settings.threshold + offset).toStringAsFixed(2)}'
                      '${offset == 0 ? '' : ' (${offset > 0 ? '+' : ''}${offset.toStringAsFixed(2)})'}',
                      style: theme.panelStyle(color: theme.accent),
                    ),
                  ],
                ),
                Slider(
                  value: offset,
                  min: -0.15,
                  max: 0.15,
                  divisions: 30,
                  onChanged: (v) => controller.setThresholdOffset(current, (v * 100).round() / 100),
                ),
                Text(
                  inView == null
                      ? 'LOWER IF THIS ADMIN IS OFTEN MISSED, RAISE IF OTHERS PASS AS THEM.'
                      : 'IN VIEW NOW: MATCH ${(inView.similarity * 100).toStringAsFixed(0)}%',
                  style: theme.panelStyle(size: 10, color: inView == null ? theme.panelDim : theme.accent),
                ),
                SheetSection('SCANS', theme: theme),
                _Action(theme, '> ADD A LOOK (GLASSES, MASK, BEARD...)', () => close(() => _extend(sheetContext, current))),
                _Action(theme, '> RE-SCAN FROM SCRATCH', () => close(() => _rescan(sheetContext, current))),
                _Action(theme, '> DELETE ADMIN', () => close(() => _delete(sheetContext, current)), danger: true),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, Identity admin) async {
    final confirmed = await confirmAction(
      context,
      theme: controller.settings.theme,
      title: 'DELETE ADMIN',
      message: 'DELETE ${admin.displayName}? THE MACHINE WILL NO LONGER RECOGNISE THIS FACE AS ADMIN.',
      action: 'DELETE',
      danger: true,
    );
    if (confirmed) await controller.deleteIdentity(admin);
  }

  @override
  Widget build(BuildContext context) {
    // The controller also notifies when the identity store changes.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = controller.settings.theme;
        final admins = controller.identities.admins;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle('ADMIN PROFILES', theme: theme),
            const SizedBox(height: 12),
            if (admins.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('NO ADMIN PROFILES', style: theme.panelStyle(color: theme.panelDim)),
              ),
            for (final admin in admins)
              IdentityRow(
                identity: admin,
                store: controller.identities,
                theme: theme,
                subtitle: controller.subjects.any(
                      (s) => s.displayDesignation == Designation.admin && identical(s.identity, admin),
                    )
                    ? 'IN VIEW'
                    : '${admin.embeddings.length} + ${admin.learned.length} SAMPLES',
                highlight: controller.subjects.any((s) => identical(s.identity, admin)),
                actions: [
                  IdentityAction(Icons.edit_outlined, 'RENAME', () => _rename(context, admin)),
                  IdentityAction(Icons.tune, 'PROFILE', () => _details(context, admin)),
                ],
              ),
            Divider(color: theme.panelDim.withValues(alpha: 0.3), height: 20),
            InkWell(
              onTap: () => _add(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('> ADD ADMIN', style: theme.panelStyle(color: theme.accent)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class IdentityAction {
  const IdentityAction(this.icon, this.tooltip, this.onPressed, {this.danger = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;
}

/// A face thumbnail, name and actions for one known identity.
class IdentityRow extends StatelessWidget {
  const IdentityRow({
    super.key,
    required this.identity,
    required this.store,
    required this.theme,
    required this.subtitle,
    required this.actions,
    this.title,
    this.highlight = false,
  });

  final Identity identity;
  final IdentityStore store;
  final ModeTheme theme;
  final String? title;
  final String subtitle;
  final List<IdentityAction> actions;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final file = store.thumbnailFile(identity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              border: Border.all(color: highlight ? theme.accent : theme.panelDim.withValues(alpha: 0.4)),
              color: Colors.black,
            ),
            child: file == null
                ? Icon(Icons.person_outline, color: theme.dim)
                : ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.25, 0.65, 0.1, 0, 0, //
                      0.25, 0.65, 0.1, 0, 0, //
                      0.27, 0.68, 0.12, 0, 0, //
                      0, 0, 0, 1, 0, //
                    ]),
                    child: Image.file(file, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title ?? identity.displayName, style: theme.panelStyle(size: 14, color: theme.accent)),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.panelStyle(size: 10, color: highlight ? theme.accent : theme.panelDim)),
              ],
            ),
          ),
          for (final action in actions)
            IconButton(
              tooltip: action.tooltip,
              onPressed: action.onPressed,
              icon: Icon(action.icon, size: 20, color: action.danger ? theme.alert : theme.panelText),
            ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.theme, this.label, this.onTap, {this.danger = false});

  final ModeTheme theme;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Text(label, style: theme.panelStyle(color: danger ? theme.alert : null)),
    ),
  );
}
