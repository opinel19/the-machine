import 'mode.dart';

/// How the Machine classifies a face it is looking at.
///
/// Mirrors the show's colour-coded boxes: white for everyone it monitors,
/// yellow for people who know about it, red for threats, black with yellow
/// corners for its analog interface, blue for government catalysts, and white
/// with red corners for irrelevant threats.
enum Designation {
  /// Just acquired; not identified yet.
  analyzing,

  /// Matches an admin, waiting for a blink before trusting it.
  verifying,

  irrelevant,

  /// An irrelevant subject whose number the Machine just gave out.
  personOfInterest,

  admin,
  asset,
  analogInterface,
  catalyst,
  relevant,
  threat,
  perpetrator;

  /// Designations the user can give someone by long-pressing their box.
  static const assignable = [relevant, threat, perpetrator, asset, analogInterface, catalyst];

  /// The label each system puts on it. Samaritan sees the Machine's people
  /// as its targets: admins and the analog interface are priority targets.
  String label(MachineMode mode) => switch ((mode, this)) {
    (MachineMode.machine, analyzing) => 'ANALYZING',
    (MachineMode.machine, verifying) => 'VERIFYING',
    (MachineMode.machine, irrelevant) => 'IRRELEVANT',
    (MachineMode.machine, personOfInterest) => 'PERSON OF INTEREST',
    (MachineMode.machine, admin) => 'ADMIN',
    (MachineMode.machine, asset) => 'ASSET',
    (MachineMode.machine, analogInterface) => 'ANALOG INTERFACE',
    (MachineMode.machine, catalyst) => 'CATALYST',
    (MachineMode.machine, relevant) => 'RELEVANT',
    (MachineMode.machine, threat) => 'THREAT',
    (MachineMode.machine, perpetrator) => 'PERPETRATOR',
    (MachineMode.samaritan, analyzing || verifying) => 'ANALYZING',
    (MachineMode.samaritan, irrelevant || personOfInterest) => 'IRRELEVANT',
    (MachineMode.samaritan, admin || analogInterface) => 'PRIORITY TARGET',
    (MachineMode.samaritan, asset) => 'TARGET',
    (MachineMode.samaritan, catalyst) => 'ASSET',
    (MachineMode.samaritan, relevant) => 'THREAT',
    (MachineMode.samaritan, threat) => 'ENEMY COMBATANT',
    (MachineMode.samaritan, perpetrator) => 'DEVIANT',
  };

  /// Showing up with one of these raises an alert.
  bool get alerts => this == relevant || this == threat;

  /// Whether this is a settled verdict rather than a transient state.
  bool get settled => this != analyzing && this != verifying;
}
