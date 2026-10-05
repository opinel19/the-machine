import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/machine/designation.dart';
import 'package:person_of_interest/src/machine/people_tracker.dart';
import 'package:person_of_interest/src/machine/subject.dart';
import 'package:person_of_interest/src/vision/body.dart';

void main() {
  // An upper body, and the face that would be on it.
  final person = Person(const Rect.fromLTWH(100, 100, 300, 500));
  final faceBox = Rect.fromCenter(center: person.head.center, width: 90, height: 110);
  var nextId = 100;
  Subject create(int now) => Subject(id: nextId++, number: 4821, firstSeenMs: now);

  Subject face(int id, int seenMs, {Designation designation = Designation.admin}) =>
      Subject(id: id, number: 1000 + id, firstSeenMs: 0)
        ..observe(faceBox, seenMs)
        ..designation = designation;

  test('someone facing the camera is left to the face tracker', () {
    final subjects = {1: face(1, 1000)};
    trackPeople(subjects, [person], 1000, () => create(1000));
    expect(subjects, hasLength(1));
    expect(subjects[1]!.rear, isFalse);
  });

  test('a face that turned away keeps its subject, and who they are', () {
    final subjects = {1: face(1, 1000)};
    trackPeople(subjects, [person], 1400, () => create(1400));
    expect(subjects, hasLength(1));
    final admin = subjects[1]!;
    expect(admin.rear, isTrue);
    expect(admin.designation, Designation.admin);
    expect(admin.box, person.head);
    expect(admin.lastSeenMs, 1400);
  });

  test('someone new from behind is irrelevant, and followed from pass to pass', () {
    final subjects = <int, Subject>{};
    trackPeople(subjects, [person], 1000, () => create(1000));
    final stranger = subjects.values.single;
    expect(stranger.rear, isTrue);
    expect(stranger.designation, Designation.irrelevant);
    final moved = Person(const Rect.fromLTWH(120, 104, 300, 500));
    trackPeople(subjects, [moved], 1100, () => create(1100));
    expect(subjects.values.single, same(stranger));
    expect(stranger.box, moved.head);
  });

  test('two people are two subjects', () {
    final subjects = <int, Subject>{};
    final other = Person(const Rect.fromLTWH(700, 120, 280, 480));
    trackPeople(subjects, [person, other], 1000, () => create(1000));
    trackPeople(subjects, [other, person], 1100, () => create(1100));
    expect(subjects, hasLength(2));
    expect(subjects.values.every((s) => s.lastSeenMs == 1100), isTrue);
  });
}
