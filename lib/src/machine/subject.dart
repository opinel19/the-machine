import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../storage/identity_store.dart';
import '../vision/face_embedder.dart';
import 'designation.dart';
import 'liveness.dart';

/// A face the Machine is tracking across camera frames.
class Subject {
  Subject({required this.id, required this.number, required this.firstSeenMs}) : lastSeenMs = firstSeenMs;

  static const _maxEmbeddings = 8;

  /// Stable key. ML Kit's [trackingId] changes when it loses a face for a
  /// moment and finds it again; the subject survives that.
  final int id;
  int? trackingId;

  /// Four-digit number shown next to the box.
  final int number;
  final int firstSeenMs;
  int lastSeenMs;

  /// Face bounding box in upright frame pixels.
  Rect box = Rect.zero;

  /// How far the face moved since the previous frame, in face widths.
  double motion = 0;

  /// Found by body, not face: facing away or too far. [box] is then an
  /// estimate of where the face would be, so the mark sits on the head.
  bool rear = false;

  /// A "face" found in near-black, featureless pixels (a covered lens):
  /// tracked so it does not come back as new, but never shown.
  bool ghost = false;
  int lastLightCheckMs = -1 << 30;

  /// Eye (and, when found, mouth corner) positions used to align the face,
  /// left-to-right as they appear in the frame. Null without landmarks.
  List<double>? alignPoints;

  /// Head rotation in degrees (left/right and up/down).
  double yaw = 0;
  double pitch = 0;

  /// Probability both eyes are open; null unless liveness checks are on.
  double? eyesOpen;
  final blink = BlinkDetector();

  /// Blinked at least once, so it is not a photo.
  bool get live => blink.blinked;

  /// Most recent embeddings of this face and their mean direction.
  final List<Float32List> embeddings = [];
  Float32List? signature;
  int lastEmbeddingMs = -1 << 30;

  /// Latest aligned 112x112 RGB face and its sharpness.
  Uint8List? lastFace;
  double sharpness = 0;

  Designation designation = Designation.analyzing;
  Identity? identity;

  /// Similarity of [signature] to the closest known identity.
  double similarity = 0;

  /// The social security number the Machine gave out for this subject.
  String? issuedNumber;

  /// Last designation reported in the event log.
  Designation? announced;

  String get code => 'SUBJ-$number';

  /// What the interface shows: an irrelevant subject whose number came up is
  /// a person of interest.
  Designation get displayDesignation =>
      issuedNumber != null && designation == Designation.irrelevant ? Designation.personOfInterest : designation;

  /// Rough distance to a face of average width, for the interface only.
  double distanceMeters(double focalPixels) => 0.15 * focalPixels / math.max(box.width, 1);

  /// Sample eagerly until the verdict is stable, then keep re-checking.
  int get embeddingIntervalMs => embeddings.length < 3
      ? 0
      : embeddings.length < _maxEmbeddings
      ? 250
      : 1000;

  void observe(Rect newBox, int nowMs) {
    motion = box == Rect.zero ? 0 : (newBox.center - box.center).distance / math.max(newBox.width, 1);
    box = newBox;
    lastSeenMs = nowMs;
  }

  void addEmbedding(Float32List embedding, int nowMs) {
    // A tracker can hop onto another face (two people crossing paths). Start
    // over when a sample clearly belongs to someone else.
    final current = signature;
    if (current != null && embeddings.length >= 3 && cosine(embedding, current) < 0.2) {
      reset();
    }
    embeddings.add(embedding);
    if (embeddings.length > _maxEmbeddings) embeddings.removeAt(0);
    signature = meanDirection(embeddings);
    lastEmbeddingMs = nowMs;
  }

  void reset() {
    embeddings.clear();
    signature = null;
    identity = null;
    similarity = 0;
    designation = Designation.analyzing;
    announced = null;
    lastEmbeddingMs = -1 << 30;
  }
}
