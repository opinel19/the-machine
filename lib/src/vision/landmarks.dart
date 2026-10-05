import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Eye and mouth-corner positions of [face] in the order `alignFace`
/// expects (left to right as seen in the image), or null without eyes.
List<double>? alignmentPointsOf(Face face) {
  math.Point<int>? at(FaceLandmarkType type) => face.landmarks[type]?.position;

  // ML Kit names landmarks from the subject's point of view, so their right
  // eye is the one on the image's left.
  final a = at(FaceLandmarkType.rightEye), b = at(FaceLandmarkType.leftEye);
  if (a == null || b == null || a.distanceTo(b) < 8) return null;
  final swap = a.x > b.x;
  final eyeL = swap ? b : a, eyeR = swap ? a : b;
  final m1 = at(FaceLandmarkType.rightMouth), m2 = at(FaceLandmarkType.leftMouth);
  final mouthL = swap ? m2 : m1, mouthR = swap ? m1 : m2;
  return [
    eyeL.x.toDouble(), eyeL.y.toDouble(),
    eyeR.x.toDouble(), eyeR.y.toDouble(),
    if (mouthL != null && mouthR != null) ...[
      mouthL.x.toDouble(), mouthL.y.toDouble(),
      mouthR.x.toDouble(), mouthR.y.toDouble(),
    ],
  ];
}
