import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/machine/designation.dart';
import 'package:person_of_interest/src/storage/identity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A unit vector along axis [i] of a 4-d space.
Float32List axis(int i) => Float32List(4)..[i] = 1;

String encode(Float32List v) => base64Encode(v.buffer.asUint8List());

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('identities');
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => dir.delete(recursive: true));

  IdentityStore store() => IdentityStore(directory: () async => dir);

  test('a profile from the SharedPreferences era moves into the file as ADMIN 01', () async {
    SharedPreferences.setMockInitialValues({
      'poi.identities.v1': jsonEncode([
        {
          'id': 'ADMIN',
          'designation': 'admin',
          'embeddings': [encode(axis(0))],
        },
      ]),
    });
    final first = store();
    await first.load();
    expect(first.admins.single.name, 'ADMIN 01');
    expect((await SharedPreferences.getInstance()).getString('poi.identities.v1'), isNull);

    final reloaded = store();
    await reloaded.load();
    expect(reloaded.admins.single.name, 'ADMIN 01');
    expect(reloaded.suggestAdminName(), 'ADMIN 02');
  });

  test('identities of every kind are matched and persisted independently', () async {
    final s = store();
    await s.load();

    final emir = await s.add(Designation.admin, [axis(0)], name: 'emir');
    final seyma = await s.add(Designation.admin, [axis(1)], name: '  şeyma  ');
    await s.add(Designation.threat, [axis(2)], thumbnailPng: Uint8List.fromList([1, 2, 3]));

    expect(s.admins.map((a) => a.name), ['EMIR', 'SEYMA']);
    expect(s.bestMatch(axis(1))!.identity, same(seyma));
    bool isAdmin(Identity i) => i.designation == Designation.admin;
    expect(s.bestMatch(axis(2), where: isAdmin)!.similarity, 0);
    expect(s.bestMatch(axis(0), where: isAdmin, excluding: emir)!.identity, same(seyma));

    final renamed = await s.update(emir, name: 'Emir Ö');
    expect(renamed.name, 'EMIR Ö');
    expect(renamed.id, emir.id);

    final reloaded = store();
    await reloaded.load();
    expect(reloaded.admins.map((a) => a.name), ['EMIR Ö', 'SEYMA']);
    final threat = reloaded.flagged.single;
    expect(threat.designation, Designation.threat);
    expect(reloaded.thumbnailFile(threat)!.readAsBytesSync(), [1, 2, 3]);
  });

  test('learned samples are capped and a re-scan clears them', () async {
    final s = store();
    await s.load();
    var admin = await s.add(Designation.admin, [axis(0)], name: 'a');
    for (var i = 0; i < IdentityStore.maxLearned + 5; i++) {
      admin = s.learn(admin, axis(1));
    }
    expect(admin.learned, hasLength(IdentityStore.maxLearned));

    final rescanned = await s.update(admin, embeddings: [axis(2)]);
    expect(rescanned.learned, isEmpty);
    expect(rescanned.embeddings.single, axis(2));
  });

  test('removeLookalikes only drops identities that match the face', () async {
    final s = store();
    await s.load();
    await s.add(Designation.relevant, [axis(0)]);
    await s.add(Designation.relevant, [axis(3)]);

    await s.removeLookalikes(Designation.relevant, axis(0), 0.4);

    expect(s.count(Designation.relevant), 1);
    expect(s.bestMatch(axis(3))!.similarity, closeTo(1, 1e-6));
  });

  test('normalizeName upper-cases and folds letters the font lacks', () {
    expect(IdentityStore.normalizeName('  ağaç   şişe İz '), 'AGAÇ SISE IZ');
  });
}
