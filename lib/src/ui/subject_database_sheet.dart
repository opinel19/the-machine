import 'package:flutter/material.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../storage/identity_store.dart';
import '../theme.dart';
import 'admin_sheet.dart';
import 'designation_menu.dart';
import 'dialogs.dart';
import 'sheet.dart';

/// Everyone the user gave a designation: their face, name and designation,
/// each of which can be changed or forgotten.
Future<void> showSubjectDatabase(BuildContext context, MachineController controller) {
  return showMachineSheet<void>(
    context,
    theme: controller.settings.theme,
    builder: (context) => _SubjectDatabase(controller: controller),
  );
}

class _SubjectDatabase extends StatelessWidget {
  const _SubjectDatabase({required this.controller});

  final MachineController controller;

  Future<void> _rename(BuildContext context, Identity identity) async {
    final name = await askName(context, theme: controller.settings.theme, title: 'NAME SUBJECT', initial: identity.name ?? '');
    if (name != null) await controller.renameIdentity(identity, name);
  }

  Future<void> _redesignate(BuildContext context, Identity identity) async {
    final designation = await pickDesignation(
      context,
      settings: controller.settings,
      subjectLabel: identity.displayName,
      current: identity.designation,
    );
    if (designation == null) return;
    if (!Designation.assignable.contains(designation)) {
      await controller.deleteIdentity(identity);
    } else {
      await controller.redesignate(identity, designation);
    }
  }

  Future<void> _delete(BuildContext context, Identity identity) async {
    final confirmed = await confirmAction(
      context,
      theme: controller.settings.theme,
      title: 'FORGET SUBJECT',
      message: 'FORGET ${identity.displayName}? THEIR FACE AND DESIGNATION WILL BE DELETED.',
      action: 'FORGET',
      danger: true,
    );
    if (confirmed) await controller.deleteIdentity(identity);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = controller.settings.theme;
        final mode = controller.settings.mode;
        final flagged = controller.identities.flagged;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(theme.isSamaritan ? 'SUBJECT REGISTRY' : 'SUBJECT DATABASE', theme: theme),
            const SizedBox(height: 4),
            Text(
              'TAP A BOX TO FLAG AS RELEVANT. HOLD IT FOR OTHER DESIGNATIONS.',
              style: theme.panelStyle(size: 10, color: theme.panelDim),
            ),
            const SizedBox(height: 10),
            if (flagged.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('NO SUBJECTS ON FILE', style: theme.panelStyle(color: theme.panelDim)),
              ),
            for (final identity in flagged)
              IdentityRow(
                identity: identity,
                store: controller.identities,
                theme: theme,
                title: identity.name ?? identity.id,
                subtitle: identity.designation.label(mode),
                highlight: controller.subjects.any((s) => identical(s.identity, identity)),
                actions: [
                  IdentityAction(Icons.edit_outlined, 'NAME', () => _rename(context, identity)),
                  IdentityAction(Icons.label_outline, 'DESIGNATE', () => _redesignate(context, identity)),
                  IdentityAction(Icons.delete_outline, 'FORGET', () => _delete(context, identity), danger: true),
                ],
              ),
          ],
        );
      },
    );
  }
}
