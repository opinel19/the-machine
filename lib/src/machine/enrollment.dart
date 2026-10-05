import 'dart:typed_data';

import '../storage/identity_store.dart';
import '../vision/face_embedder.dart';
import 'feed.dart';

enum EnrollmentHint {
  noFace('NO FACE DETECTED'),
  multipleFaces('ONLY ONE FACE MAY BE IN VIEW'),
  moveCloser('MOVE CLOSER'),
  holdStill('HOLD STILL'),
  faceCamera('LOOK AT THE CAMERA'),
  scanning('HOLD STILL. TURN YOUR HEAD SLOWLY');

  const EnrollmentHint(this.text);

  final String text;
}

/// An in-progress scan of an admin's face.
class Enrollment {
  Enrollment({required this.returnTo, required this.name, this.replacing, this.extending});

  static const sampleCount = 15;
  static const _minIntervalMs = 140;

  /// Camera to switch back to if the scan is aborted.
  final Feed returnTo;

  /// Name of the admin being scanned.
  final String name;

  /// The admin profile a re-scan replaces; null for a new admin.
  final Identity? replacing;

  /// The admin profile an extra scan adds to (glasses, a mask, a new look).
  final Identity? extending;

  final List<Float32List> samples = [];
  EnrollmentHint hint = EnrollmentHint.noFace;
  bool finished = false;

  /// What happened, shown once [finished].
  String? result;

  /// Sharpest aligned face seen, kept as the profile picture.
  Uint8List? bestFace;
  double _bestSharpness = -1;

  void offerFace(Uint8List face, double sharpness) {
    if (sharpness > _bestSharpness) {
      bestFace = face;
      _bestSharpness = sharpness;
    }
  }
  int _lastSampleMs = -1 << 30;

  double get progress => samples.length / sampleCount;
  bool get complete => samples.length >= sampleCount;
  bool readyForSample(int nowMs) => nowMs - _lastSampleMs >= _minIntervalMs;

  void add(Float32List embedding, int nowMs) {
    samples.add(embedding);
    _lastSampleMs = nowMs;
  }

  /// Whether every sample plausibly shows the same person.
  bool get consistent {
    final centroid = meanDirection(samples);
    return samples.every((s) => cosine(s, centroid) >= 0.5);
  }
}
