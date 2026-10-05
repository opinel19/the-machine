import 'package:flutter/material.dart';

import '../machine/designation.dart';
import '../machine/machine_controller.dart';
import '../storage/settings.dart';
import '../theme.dart';
import 'sheet.dart';

Future<void> showSettingsSheet(
  BuildContext context,
  MachineController controller, {
  required VoidCallback onManageAdmins,
  required VoidCallback onSubjectDatabase,
  required VoidCallback onNumberHistory,
  required VoidCallback onTalk,
  required VoidCallback onMap,
}) {
  return showMachineSheet<void>(
    context,
    theme: controller.settings.theme,
    builder: (context) => _SettingsSheet(
      controller: controller,
      onManageAdmins: onManageAdmins,
      onSubjectDatabase: onSubjectDatabase,
      onNumberHistory: onNumberHistory,
      onTalk: onTalk,
      onMap: onMap,
    ),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.controller,
    required this.onManageAdmins,
    required this.onSubjectDatabase,
    required this.onNumberHistory,
    required this.onTalk,
    required this.onMap,
  });

  final MachineController controller;

  /// Open other sheets; called after this one closes.
  final VoidCallback onManageAdmins;
  final VoidCallback onSubjectDatabase;
  final VoidCallback onNumberHistory;
  final VoidCallback onTalk;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final identities = controller.identities;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, identities]),
      builder: (context, _) {
        // The sheet restyles itself when the mode switches.
        final theme = settings.theme;
        String two(int n) => n.toString().padLeft(2, '0');
        Widget toggle(String label, bool value, ValueChanged<bool> onChanged, {String? hint}) =>
            _SwitchRow(theme: theme, label: label, hint: hint, value: value, onChanged: onChanged);
        return Theme(
          data: theme.isSamaritan ? samaritanTheme() : machineTheme(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitle('SYSTEM CONFIGURATION', theme: theme),
              SheetSection('SYSTEM', theme: theme),
              _ModeSwitch(settings: settings, theme: theme),
              _ActionRow(
                theme: theme,
                label: theme.isSamaritan ? 'QUERY SAMARITAN' : 'TALK TO THE MACHINE',
                onTap: () {
                  Navigator.pop(context);
                  onTalk();
                },
              ),
              if (!theme.isSamaritan) ...[
                const SizedBox(height: 4),
                Text('BOX STYLE', style: theme.panelStyle(size: 10, color: theme.panelDim)),
                const SizedBox(height: 6),
                _SeasonSwitch(settings: settings, theme: theme),
              ],
              SheetSection('RECOGNITION', theme: theme),
              Row(
                children: [
                  Text('MATCH THRESHOLD', style: theme.panelStyle()),
                  const Spacer(),
                  Text(settings.threshold.toStringAsFixed(2), style: theme.panelStyle(color: theme.accent)),
                ],
              ),
              Slider(
                value: settings.threshold,
                min: MachineSettings.minThreshold,
                max: MachineSettings.maxThreshold,
                divisions: 45,
                onChanged: (value) => settings.threshold = value,
              ),
              Text(
                'LOWER IT IF AN ADMIN IS MISSED. RAISE IT IF OTHERS ARE CALLED ADMIN.',
                style: theme.panelStyle(size: 10, color: theme.panelDim),
              ),
              toggle('LIVENESS CHECK', settings.liveness, (v) => settings.liveness = v, hint: 'ADMINS MUST BLINK. A PHOTO WILL NOT PASS.'),
              toggle('PROFILE LEARNING', settings.learning, (v) => settings.learning = v, hint: 'ADMIN PROFILES ABSORB NEW ANGLES AND LIGHT.'),
              toggle('LONG RANGE', settings.longRange, (v) => settings.longRange = v, hint: '1080P AND SMALLER FACES. USES MORE POWER.'),
              toggle('NIGHT MODE', settings.nightMode, (v) => settings.nightMode = v, hint: 'IN THE DARK: MORE EXPOSURE, BRIGHTER FACES.'),
              SheetSection('FEED', theme: theme),
              toggle(theme.isSamaritan ? 'SAMARITAN FILTER' : 'MACHINE VISION FILTER', settings.machineVision, (v) => settings.machineVision = v),
              toggle('VEHICLES & AIRCRAFT', settings.vehicles, (v) => settings.vehicles = v, hint: 'CARS, BOATS AND PLANES GET THEIR OWN MARKS.'),
              toggle('PEOPLE FACING AWAY', settings.bodies, (v) => settings.bodies = v, hint: 'A BOX FOR EVERYONE, FACE IN VIEW OR NOT.'),
              toggle('LOCATION', settings.location, (v) => settings.location = v, hint: 'GPS POSITION ON THE FEED, CAPTURES AND NUMBERS.'),
              toggle('SHOW SCORES', settings.showScores, (v) => settings.showScores = v),
              toggle('EVENT LOG', settings.eventLog, (v) => settings.eventLog = v),
              SheetSection('VOICE & ALERTS', theme: theme),
              toggle('VOICE', settings.voice, (v) => settings.voice = v, hint: 'GREETINGS, ALERTS AND NUMBERS, OUT LOUD.'),
              toggle('THREAT ALERTS', settings.alerts, (v) => settings.alerts = v),
              toggle('RANDOM CRASHES', settings.crashes, (v) => settings.crashes = v, hint: 'NOW AND THEN THE SYSTEM FAILS AND REBOOTS.'),
              _ActionRow(
                theme: theme,
                label: 'SIMULATE SYSTEM CRASH',
                onTap: () {
                  Navigator.pop(context);
                  controller.triggerCrash();
                },
              ),
              SheetSection('SECURITY', theme: theme),
              toggle('ADMIN LOCK', settings.adminLock, (v) => settings.adminLock = v, hint: 'ADMIN AND SYSTEM OPEN ONLY FOR A RECOGNISED ADMIN.'),
              SheetSection('DATA', theme: theme),
              _ActionRow(
                theme: theme,
                label: 'ADMIN PROFILES (${two(identities.admins.length)})',
                onTap: () {
                  Navigator.pop(context);
                  onManageAdmins();
                },
              ),
              _ActionRow(
                theme: theme,
                label: '${theme.isSamaritan ? 'SUBJECT REGISTRY' : 'SUBJECT DATABASE'} (${two(identities.flagged.length)})',
                onTap: () {
                  Navigator.pop(context);
                  onSubjectDatabase();
                },
              ),
              _ActionRow(
                theme: theme,
                label: 'NUMBER HISTORY (${two(controller.numbers.records.length)})',
                onTap: () {
                  Navigator.pop(context);
                  onNumberHistory();
                },
              ),
              _ActionRow(
                theme: theme,
                label: theme.isSamaritan ? 'GLOBAL VIEW' : 'SURVEILLANCE MAP',
                onTap: () {
                  Navigator.pop(context);
                  onMap();
                },
              ),
              _ActionRow(
                theme: theme,
                label: 'FORGET ALL FLAGGED SUBJECTS',
                danger: true,
                onTap: identities.flagged.isEmpty
                    ? null
                    : () async {
                        for (final designation in Designation.assignable) {
                          await identities.removeAll(designation);
                        }
                      },
              ),
              SheetSection('GESTURES', theme: theme),
              for (final line in const [
                'TAP THE SYSTEM NAME (TOP LEFT): TALK TO IT',
                'TAP A BOX: FLAG AS RELEVANT',
                'TAP A THREAT: RUN A SIMULATION',
                'DOUBLE TAP A BOX: ENHANCE',
                'HOLD A BOX: DESIGNATE, CLEAR OR SIMULATE',
                'CAPTURE: TAP FOR A PHOTO, HOLD TO RECORD',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(line, style: theme.panelStyle(size: 10, color: theme.panelDim)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.settings, required this.theme});

  final MachineSettings settings;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    Widget option(MachineMode mode, String label) {
      final selected = settings.mode == mode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            // The switch plays a full-screen transition; the sheet would
            // otherwise keep the old system's colours.
            Navigator.pop(context);
            settings.mode = mode;
          },
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? theme.accent : Colors.transparent,
              border: Border.all(color: selected ? theme.accent : theme.panelDim.withValues(alpha: 0.5)),
            ),
            child: Text(
              label,
              style: theme.panelStyle(
                size: 12,
                color: selected ? (theme.isSamaritan ? Colors.white : Colors.black) : theme.panelText,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(MachineMode.machine, 'THE MACHINE'),
        const SizedBox(width: 8),
        option(MachineMode.samaritan, 'SAMARITAN'),
      ],
    );
  }
}

class _SeasonSwitch extends StatelessWidget {
  const _SeasonSwitch({required this.settings, required this.theme});

  final MachineSettings settings;
  final ModeTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (season, label) in const [(1, 'S1'), (2, 'S2'), (3, 'S3-5')])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => settings.season = season,
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: settings.season == season ? theme.accent : Colors.transparent,
                    border: Border.all(color: theme.panelDim.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    label,
                    style: theme.panelStyle(size: 11, color: settings.season == season ? Colors.black : theme.panelText),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.theme,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final ModeTheme theme;
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hint = this.hint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.panelStyle()),
                if (hint != null) Text(hint, style: theme.panelStyle(size: 9, color: theme.panelDim, spacing: 1)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.theme, required this.label, this.onTap, this.danger = false});

  final ModeTheme theme;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? theme.panelDim
        : danger
        ? theme.alert
        : theme.panelText;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Text('> $label', style: theme.panelStyle(color: color)),
      ),
    );
  }
}
