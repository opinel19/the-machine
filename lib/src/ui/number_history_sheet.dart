import 'package:flutter/material.dart';

import '../machine/machine_controller.dart';
import '../storage/number_log.dart';
import '../theme.dart';
import 'map_view.dart';
import 'sheet.dart';

/// Every number the Machine gave out: whose face, when, and whether they
/// turned up again.
Future<void> showNumberHistory(BuildContext context, MachineController controller) {
  return showMachineSheet<void>(
    context,
    theme: controller.settings.theme,
    builder: (context) => ListenableBuilder(
      listenable: controller.numbers,
      builder: (context, _) {
        final theme = controller.settings.theme;
        final records = controller.numbers.records;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle('NUMBER HISTORY', theme: theme),
            const SizedBox(height: 10),
            if (records.any((r) => r.latitude != null))
              InkWell(
                onTap: () => showSurveillanceMap(context, controller),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('> SHOW ON MAP', style: theme.panelStyle(color: theme.accent)),
                ),
              ),
            if (records.isEmpty)
              Text('NO NUMBERS GIVEN OUT YET.', style: theme.panelStyle(color: theme.panelDim)),
            for (final record in records) _NumberRow(record: record, controller: controller, theme: theme),
            if (records.isNotEmpty)
              InkWell(
                onTap: controller.numbers.clear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('> CLEAR HISTORY', style: theme.panelStyle(color: theme.alert)),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.record, required this.controller, required this.theme});

  final NumberRecord record;
  final MachineController controller;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    String stamp(DateTime t) => '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    final face = record.facePng;
    final inView = controller.subjects.any((s) => s.issuedNumber == record.ssn);
    final seen = record.sightings == 0
        ? 'NOT SEEN SINCE'
        : 'SEEN AGAIN ${record.sightings}x · LAST ${stamp(record.lastSeenAt)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: inView ? theme.accent : theme.panelDim.withValues(alpha: 0.4)),
            ),
            child: face == null
                ? Icon(Icons.person_outline, color: theme.dim)
                : Image.memory(face, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.ssn, style: theme.panelStyle(size: 15, color: theme.accent, spacing: 2)),
                Text(
                  'ISSUED ${stamp(record.issuedAt)} · ${record.subjectCode}',
                  style: theme.panelStyle(size: 10, color: theme.panelDim, spacing: 1),
                ),
                if (record.place case final place?)
                  Text('AT $place', style: theme.panelStyle(size: 10, color: theme.panelDim, spacing: 1)),
                Text(
                  inView ? 'IN VIEW NOW' : seen,
                  style: theme.panelStyle(size: 10, color: inView ? theme.accent : theme.panelDim, spacing: 1),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'DELETE',
            onPressed: () => controller.numbers.remove(record),
            icon: Icon(Icons.delete_outline, size: 20, color: theme.alert),
          ),
        ],
      ),
    );
  }
}
