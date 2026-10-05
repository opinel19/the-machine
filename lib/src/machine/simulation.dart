import 'dart:math' as math;

import 'designation.dart';
import 'mode.dart';

/// One simulated course of action: a choice at each level of the tree and
/// how it ends.
class SimulationRun {
  const SimulationRun({
    required this.index,
    required this.path,
    required this.outcome,
    required this.success,
    required this.probability,
  });

  /// Which simulation this was, out of [SimulationPlan.total].
  final int index;

  /// The child taken at each level, starting below the root.
  final List<int> path;
  final String outcome;
  final bool success;

  /// Chance this course ends well, 0-1.
  final double probability;
}

/// The Machine (or Samaritan) trying courses of action for a subject and
/// settling on one, like the simulations in "If-Then-Else". Worked out up
/// front; the simulation view plays it back.
class SimulationPlan {
  SimulationPlan._({
    required this.subject,
    required this.mode,
    required this.total,
    required this.actions,
    required this.runs,
    required this.verdict,
    required this.metric,
    required this.percent,
    required this.courseLabel,
    required this.coursePercent,
  });

  /// Children per node at each level below the root.
  static const branching = [3, 3, 2];
  static const failedRuns = 4;

  /// [seed] fixes the verdict (use something stable per subject); [attempt]
  /// varies the tree and the runs, so running it again explores anew.
  factory SimulationPlan.generate({
    required String subject,
    required Designation designation,
    required MachineMode mode,
    required int seed,
    int attempt = 0,
  }) {
    final samaritan = mode == MachineMode.samaritan;
    final verdict = _verdictFor(designation, samaritan, math.Random(seed));
    final random = math.Random(seed * 7919 + attempt);
    final vocabulary = samaritan ? _samaritanActions : _machineActions;

    // Actions for every node, distinct among siblings.
    final actions = <List<String>>[];
    var nodes = 1;
    for (var level = 0; level < branching.length; level++) {
      final labels = <String>[];
      for (var parent = 0; parent < nodes; parent++) {
        labels.addAll((List.of(vocabulary[level])..shuffle(random)).take(branching[level]));
      }
      actions.add(labels);
      nodes *= branching[level];
    }

    // Failed runs on distinct paths, then the course it settles on.
    final total = samaritan ? 1000000 + random.nextInt(9000000) : 100000 + random.nextInt(900000);
    final paths = <String>{};
    List<int> freshPath() {
      while (true) {
        final path = [for (final b in branching) random.nextInt(b)];
        if (paths.add(path.join())) return path;
      }
    }

    final failures = samaritan ? _samaritanFailures : _machineFailures;
    final successes = samaritan ? _samaritanSuccesses : _machineSuccesses;
    final runs = <SimulationRun>[
      for (var i = 0; i < failedRuns; i++)
        SimulationRun(
          // 1, then further in by an order of magnitude or so each time.
          index: i == 0 ? 1 : (math.pow(total, i / (failedRuns + 0.6)) * (0.6 + random.nextDouble() * 0.8)).round(),
          path: freshPath(),
          outcome: failures[random.nextInt(failures.length)],
          success: false,
          probability: random.nextDouble() * 0.2,
        ),
    ];
    runs.add(
      SimulationRun(
        index: total ~/ 2 + random.nextInt(total ~/ 2),
        path: freshPath(),
        outcome: successes[random.nextInt(successes.length)],
        success: true,
        probability: verdict.success / 100,
      ),
    );
    return SimulationPlan._(
      subject: subject,
      mode: mode,
      total: total,
      actions: actions,
      runs: runs,
      verdict: verdict.label,
      metric: verdict.metric,
      percent: verdict.before,
      courseLabel: samaritan ? 'AFTER CORRECTION' : 'WITH INTERVENTION',
      coursePercent: verdict.after,
    );
  }

  final String subject;
  final MachineMode mode;

  /// How many simulations it claims to have run.
  final int total;

  /// Action at every node: `actions[level][node]`, see [nodeIndex].
  final List<List<String>> actions;

  /// Failures first; the last one is the course it settles on.
  final List<SimulationRun> runs;

  SimulationRun get chosen => runs.last;

  /// "ROLE: VICTIM", "CLASSIFICATION: DEVIANT", ...
  final String verdict;

  /// The headline figure and its value if nobody acts, e.g. PROBABILITY OF
  /// SURVIVAL 2.
  final String metric;
  final int percent;

  /// The same figure after the chosen course.
  final String courseLabel;
  final int coursePercent;

  /// Where [path] is at [level], as an index into `actions[level]`.
  static int nodeIndex(List<int> path, int level) {
    var index = 0;
    for (var l = 0; l <= level; l++) {
      index = index * branching[l] + path[l];
    }
    return index;
  }

  List<String> stepsOf(SimulationRun run) => [
    for (var level = 0; level < branching.length; level++) actions[level][nodeIndex(run.path, level)],
  ];

  /// "INTERVENE > DIVERT > EVACUATE".
  String get course => stepsOf(chosen).join(' > ');

  /// What the voice says at the end.
  String get spokenVerdict => '${metric.toLowerCase()}: $percent%.';

  static _Verdict _verdictFor(Designation d, bool samaritan, math.Random r) {
    int between(int low, int high) => low + r.nextInt(high - low + 1);
    if (samaritan) {
      return switch (d) {
        Designation.relevant || Designation.threat || Designation.perpetrator => _Verdict(
          'CLASSIFICATION: DEVIANT',
          'PROBABILITY OF INTERFERENCE',
          between(71, 96),
          between(0, 3),
        ),
        Designation.admin || Designation.verifying => _Verdict(
          'CLASSIFICATION: PRIORITY TARGET',
          'PROBABILITY OF ESCAPE',
          between(6, 24),
          0,
        ),
        _ => _Verdict('CLASSIFICATION: COMPLIANT', 'PROBABILITY OF DEVIATION', between(2, 14), 0),
      };
    }
    switch (d) {
      case Designation.threat:
        return _Verdict('THREAT LEVEL: CRITICAL', 'PROBABILITY OF VIOLENCE', between(84, 99), between(9, 31));
      case Designation.perpetrator:
        return _Verdict('STATUS: PERPETRATOR', 'PROBABILITY OF REOFFENDING', between(72, 95), between(18, 40));
      case Designation.admin || Designation.verifying || Designation.asset || Designation.analogInterface:
        return _Verdict('STATUS: PROTECTED', 'PROBABILITY OF SURVIVAL', between(88, 99), 99);
      case Designation.irrelevant || Designation.analyzing || Designation.catalyst:
        return _Verdict('ROLE: BYSTANDER', 'PROBABILITY OF SURVIVAL', between(86, 99), between(97, 99));
      case Designation.relevant || Designation.personOfInterest:
        // A number is a victim or a perpetrator; the simulation decides which.
        return r.nextDouble() < 0.55
            ? _Verdict('ROLE: VICTIM', 'PROBABILITY OF SURVIVAL', between(1, 9), between(52, 81))
            : _Verdict('ROLE: PERPETRATOR', 'PROBABILITY OF VIOLENCE', between(78, 97), between(12, 34));
    }
  }

  static const _machineActions = [
    ['OBSERVE', 'APPROACH', 'INTERVENE', 'CONTACT ASSET', 'ALERT POLICE', 'WAIT', 'INFILTRATE'],
    ['FOLLOW', 'CONFRONT', 'DISTRACT', 'DIVERT', 'NEGOTIATE', 'BLOCK EXIT', 'CUT POWER', 'SHADOW', 'WARN SUBJECT', 'CLONE PHONE'],
    ['DISARM', 'EVACUATE', 'SUBDUE', 'HIDE', 'RUN', 'KNEECAP', 'CALL ADMIN', 'RELOCATE', 'TRACE CALL', 'NEW IDENTITY'],
  ];
  static const _machineFailures = [
    'SUBJECT DECEASED', 'ASSET COMPROMISED', 'COVER BLOWN', 'SUBJECT ESCAPES', 'CIVILIAN CASUALTIES',
    'ASSET DECEASED', 'POLICE INTERFERENCE', 'SAMARITAN DETECTS', 'TIMELINE COLLAPSE',
  ];
  static const _machineSuccesses = ['SUBJECT SAFE', 'THREAT NEUTRALIZED', 'CRISIS AVERTED', 'SUBJECT EXTRACTED'];
  static const _samaritanActions = [
    ['SURVEIL', 'ISOLATE', 'DETAIN', 'RECRUIT', 'DISCREDIT', 'CORRECT'],
    ['TRACK', 'INTERCEPT', 'RELOCATE', 'EXPOSE', 'MANIPULATE', 'FREEZE ASSETS', 'REWRITE RECORDS', 'DEPLOY OPERATIVE'],
    ['CONTAIN', 'ERASE', 'STAGE ACCIDENT', 'ARREST', 'MONITOR', 'REPROGRAM', 'ELIMINATE'],
  ];
  static const _samaritanFailures = [
    'EXPOSURE RISK', 'OPERATIVE LOST', 'DEVIANT ESCAPES', 'MACHINE INTERFERENCE', 'PUBLIC ATTENTION', 'NARRATIVE BREACH',
  ];
  static const _samaritanSuccesses = ['OBJECTIVE ACHIEVED', 'DEVIANT CONTAINED', 'ORDER RESTORED'];
}

class _Verdict {
  const _Verdict(this.label, this.metric, this.before, this.after);

  final String label;
  final String metric;
  final int before;
  final int after;

  /// Chance the chosen course works: a better survival, or a lower risk.
  int get success => metric == 'PROBABILITY OF SURVIVAL' ? after : 100 - after;
}
