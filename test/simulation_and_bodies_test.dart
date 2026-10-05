import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/machine/designation.dart';
import 'package:person_of_interest/src/machine/mode.dart';
import 'package:person_of_interest/src/machine/simulation.dart';
import 'package:person_of_interest/src/platform/location_service.dart';
import 'package:person_of_interest/src/ui/box_painter.dart';
import 'package:person_of_interest/src/vision/body.dart';

SimulationPlan plan({
  Designation designation = Designation.relevant,
  MachineMode mode = MachineMode.machine,
  int seed = 4821,
  int attempt = 0,
}) => SimulationPlan.generate(subject: 'SUBJ-4821', designation: designation, mode: mode, seed: seed, attempt: attempt);

void main() {
  test('a simulation fails a few courses, then settles on one', () {
    final p = plan();
    expect(p.runs, hasLength(SimulationPlan.failedRuns + 1));
    expect(p.runs.take(SimulationPlan.failedRuns).every((r) => !r.success), isTrue);
    expect(p.chosen.success, isTrue);
    expect({for (final r in p.runs) r.path.join()}, hasLength(p.runs.length), reason: 'every course is different');
    for (var i = 1; i < p.runs.length; i++) {
      expect(p.runs[i].index, greaterThan(p.runs[i - 1].index), reason: 'the counter only goes up');
    }
    expect(p.chosen.index, lessThanOrEqualTo(p.total));
    expect([for (final level in p.actions) level.length], [3, 9, 18]);
    // Siblings never repeat an action.
    for (var level = 0; level < p.actions.length; level++) {
      final siblings = SimulationPlan.branching[level];
      for (var start = 0; start < p.actions[level].length; start += siblings) {
        expect(p.actions[level].sublist(start, start + siblings).toSet(), hasLength(siblings));
      }
    }
    expect(p.course.split(' > '), hasLength(3));
  });

  test('the verdict is the same for the same subject, runs vary', () {
    final a = plan(), b = plan(), again = plan(attempt: 1);
    expect(b.course, a.course);
    expect(b.percent, a.percent);
    expect(again.verdict, a.verdict);
    expect(again.percent, a.percent);
    expect(again.actions, isNot(equals(a.actions)));
  });

  test('verdicts fit the designation and the system', () {
    final number = plan(designation: Designation.personOfInterest);
    expect(number.verdict, anyOf('ROLE: VICTIM', 'ROLE: PERPETRATOR'));
    final threat = plan(designation: Designation.threat);
    expect(threat.metric, 'PROBABILITY OF VIOLENCE');
    expect(threat.percent, greaterThanOrEqualTo(84));
    expect(threat.coursePercent, lessThan(threat.percent));
    final deviant = plan(designation: Designation.threat, mode: MachineMode.samaritan);
    expect(deviant.verdict, 'CLASSIFICATION: DEVIANT');
    expect(deviant.courseLabel, 'AFTER CORRECTION');
    expect(deviant.total, greaterThanOrEqualTo(1000000));
    // Victims mostly die unless someone acts.
    for (var seed = 0; seed < 20; seed++) {
      final p = plan(seed: seed);
      if (p.verdict == 'ROLE: VICTIM') {
        expect(p.percent, lessThan(10));
        expect(p.coursePercent, greaterThan(50));
      }
    }
  });

  test('nodes are numbered level by level', () {
    expect(SimulationPlan.nodeIndex([0, 0, 0], 2), 0);
    expect(SimulationPlan.nodeIndex([2, 1, 1], 0), 2);
    expect(SimulationPlan.nodeIndex([2, 1, 1], 1), 7);
    expect(SimulationPlan.nodeIndex([2, 2, 1], 2), 17);
  });

  test('the mark of someone facing away sits on their head', () {
    // Vision's upper-body box for the man in the back-view test photo.
    const body = Rect.fromLTWH(195, 77, 564, 1008);
    final mark = headSquare(headOfBody(body));
    expect(mark.center.dx, closeTo(body.center.dx, 1));
    expect(mark.top, closeTo(body.top, body.height * 0.05));
    // About a head: a fifth to a third of the box's width.
    expect(mark.width, inInclusiveRange(body.width * 0.35, body.width * 0.6));
    expect(mark.bottom, lessThan(body.top + body.height * 0.4));

    // EfficientDet's whole-body box for the man walking away: the head is a
    // seventh of him, not 0.4 of his swinging arms.
    const walker = Rect.fromLTWH(327, 217, 156, 395);
    final small = headSquare(headOfBody(walker, wholeBody: true));
    expect(small.width, inInclusiveRange(walker.height / 8, walker.height / 5));
    expect(small.top, closeTo(walker.top, 8));
  });

  test('coordinates print the way the feeds print them', () {
    expect(formatCoordinates(40.990123, 29.029411), '40.99012°N 29.02941°E');
    expect(formatCoordinates(-33.8688, -151.2093, digits: 2), '33.87°S 151.21°W');
  });
}
