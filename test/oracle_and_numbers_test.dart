import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/machine/mode.dart';
import 'package:person_of_interest/src/machine/oracle.dart';
import 'package:person_of_interest/src/storage/number_log.dart';

OracleContext context({
  MachineMode mode = MachineMode.machine,
  List<String> admins = const [],
  int subjects = 0,
  String? place,
  String? coordinates,
}) => OracleContext(
  mode: mode,
  adminsInView: admins,
  subjectsInView: subjects,
  threatsInView: 0,
  adminCount: 2,
  now: DateTime(2026, 10, 1, 9, 5, 7),
  place: place,
  coordinates: coordinates,
);

void main() {
  final oracle = Oracle(math.Random(1));

  test('answers from what it sees, in Turkish or English', () {
    expect(oracle.answer('Ben kimim?', context(admins: ['EMIR'])).text, 'YOU ARE EMIR. ADMIN.');
    expect(oracle.answer('who am I', context()).text, contains('UNKNOWN'));
    expect(oracle.answer('Kaç kişi var?', context(subjects: 3)).text, startsWith('03 SUBJECTS IN VIEW'));
    expect(oracle.answer('saat kaç', context()).text, startsWith('09:05:07'));
    expect(oracle.answer('bana bir numara ver', context()).issueNumber, isTrue);
  });

  test('knows where it is, and runs simulations on request', () {
    final here = context(place: 'KADIKÖY, ISTANBUL', coordinates: '40.9901°N 29.0294°E');
    expect(oracle.answer('Neredeyim?', here).text, 'YOU ARE HERE: KADIKÖY, ISTANBUL. 40.9901°N 29.0294°E.');
    expect(oracle.answer('where am I', context()).text, contains('LOCATION UNKNOWN'));
    expect(
      oracle.answer('konum', context(mode: MachineMode.samaritan, coordinates: '1.0000°N 2.0000°E')).text,
      'LOCATION CONFIRMED: 1.0000°N 2.0000°E. YOU CANNOT HIDE.',
    );
    expect(oracle.answer('Simülasyon çalıştır', context()).simulate, isTrue);
    expect(oracle.answer('what will happen to him?', context()).simulate, isTrue);
    expect(oracle.answer('kimsin', context()).simulate, isFalse);
  });

  test('Samaritan has its own voice', () {
    expect(oracle.answer('merhaba', context(mode: MachineMode.samaritan)).text, 'WHAT ARE YOUR COMMANDS?');
    expect(oracle.answer('kimsin', context(mode: MachineMode.samaritan)).text, 'I AM SAMARITAN.');
    expect(oracle.answer('bir numara', context(mode: MachineMode.samaritan)).issueNumber, isFalse);
  });

  test('number history survives a restart', () async {
    final dir = await Directory.systemTemp.createTemp('numbers');
    addTearDown(() => dir.delete(recursive: true));
    final log = NumberLog(directory: () async => dir);
    await log.load();
    await log.add(NumberRecord(
      ssn: '527-81-3309',
      issuedAt: DateTime(2026, 10, 1),
      subjectCode: 'SUBJ-4821',
      signature: Float32List.fromList([0, 1, 0]),
    ));
    await log.add(NumberRecord(
      ssn: '311-40-2718',
      issuedAt: DateTime(2026, 10, 1, 12),
      subjectCode: 'SUBJ-1207',
      latitude: 40.99012,
      longitude: 29.02941,
      place: 'KADIKÖY, ISTANBUL',
    ));
    log.records.last
      ..sightings = 2
      ..lastLatitude = 41.0082
      ..lastLongitude = 28.9784;
    await log.save();

    final reloaded = NumberLog(directory: () async => dir);
    await reloaded.load();
    final [placed, first] = reloaded.records;
    expect(first.ssn, '527-81-3309');
    expect(first.sightings, 2);
    expect(first.signature, [0, 1, 0]);
    expect(first.lastLatitude, 41.0082);
    expect(first.latitude, isNull);
    expect(placed.place, 'KADIKÖY, ISTANBUL');
    expect(placed.latitude, 40.99012);
    expect(placed.longitude, 29.02941);
  });
}
