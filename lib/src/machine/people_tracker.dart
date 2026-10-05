import 'dart:math' as math;
import 'dart:ui';

import '../vision/body.dart';
import 'designation.dart';
import 'subject.dart';

/// A face missing for longer than this may be taken over by a body: the
/// person turned away. Shorter gaps are the face detector missing a frame.
const faceGraceMs = 250;

/// Gives people found by body (facing away, too far off for a face) a subject
/// with its mark on their head. Someone facing the camera is left to the face
/// tracker; a face that just turned away keeps its subject, and with it who
/// they are. [create] makes a subject for someone new.
void trackPeople(Map<int, Subject> subjects, List<Person> people, int now, Subject Function() create) {
  final taken = <Subject>{};
  for (final person in people) {
    final head = person.head;
    // Where the face of someone facing the camera would be.
    final faceZone = head.inflate(head.width);
    final facing = subjects.values.any(
      (s) => !s.rear && !s.ghost && now - s.lastSeenMs <= faceGraceMs && faceZone.contains(s.box.center),
    );
    if (facing) continue;
    Subject? best;
    var bestScore = 0.0;
    for (final s in subjects.values) {
      if (s.ghost || s.lastSeenMs == now || taken.contains(s)) continue;
      final score = s.rear
          ? math.max(iou(s.box, head), head.inflate(head.width * 0.6).contains(s.box.center) ? 0.2 : 0.0)
          : faceZone.contains(s.box.center)
          ? 0.5
          : 0.0;
      if (score > bestScore) {
        best = s;
        bestScore = score;
      }
    }
    final subject = best ?? (create()..designation = Designation.irrelevant);
    subjects[subject.id] = subject;
    taken.add(subject);
    subject
      ..rear = true
      ..trackingId = null
      ..alignPoints = null
      ..observe(head, now);
  }
}

/// Intersection over union of two boxes.
double iou(Rect a, Rect b) {
  final i = a.intersect(b);
  if (i.width <= 0 || i.height <= 0) return 0;
  final inter = i.width * i.height;
  return inter / (a.width * a.height + b.width * b.height - inter);
}
