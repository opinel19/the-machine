import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Dart side of the Core ML face embedder in `ios/Runner/AppDelegate.swift`.
class FaceEmbedder {
  static const _channel = MethodChannel('poi/face_embedder');

  Future<void> load() => _channel.invokeMethod<void>('load');

  /// Returns the L2-normalised 512-d embedding of an aligned 112x112 RGB face
  /// (see `alignFace`).
  Future<Float32List> embed(Uint8List alignedRgb) async {
    final embedding = await _channel.invokeMethod<Float32List>('embed', alignedRgb);
    return embedding!;
  }
}

/// Cosine similarity of two L2-normalised vectors.
double cosine(Float32List a, Float32List b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// Mean direction of a set of L2-normalised vectors, itself normalised.
Float32List meanDirection(Iterable<Float32List> vectors) {
  Float32List? sum;
  for (final v in vectors) {
    sum ??= Float32List(v.length);
    for (var i = 0; i < v.length; i++) {
      sum[i] += v[i];
    }
  }
  if (sum == null) throw ArgumentError.value(vectors, 'vectors', 'must not be empty');
  var norm = 0.0;
  for (final x in sum) {
    norm += x * x;
  }
  norm = math.sqrt(norm);
  if (norm > 0) {
    for (var i = 0; i < sum.length; i++) {
      sum[i] /= norm;
    }
  }
  return sum;
}
