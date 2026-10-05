import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/vision/face_align.dart';
import 'package:person_of_interest/src/vision/face_embedder.dart';

void main() {
  test('fit recovers a known similarity transform', () {
    const scale = 1.7, angle = 0.3, tx = 12.0, ty = -5.0;
    final a = scale * math.cos(angle), b = scale * math.sin(angle);
    final src = <double>[10, 20, 60, 25, 18, 70, 55, 72];
    final dst = <double>[
      for (var i = 0; i < src.length; i += 2) ...[
        a * src[i] - b * src[i + 1] + tx,
        b * src[i] + a * src[i + 1] + ty,
      ],
    ];
    final t = SimilarityTransform.fit(src, dst);
    expect(t.a, closeTo(a, 1e-9));
    expect(t.b, closeTo(b, 1e-9));
    expect(t.tx, closeTo(tx, 1e-9));
    expect(t.ty, closeTo(ty, 1e-9));
  });

  test('alignFace copies pixels 1:1 when landmarks already sit on the template', () {
    // Each pixel stores its own coordinates: R = x, G = y, B = 7.
    const width = 128, height = 128, stride = width * 4 + 64;
    final bgra = Uint8List(stride * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final p = y * stride + x * 4;
        bgra[p] = 7;
        bgra[p + 1] = y;
        bgra[p + 2] = x;
        bgra[p + 3] = 255;
      }
    }
    final rgb = alignFace(
      bgra: bgra,
      width: width,
      height: height,
      bytesPerRow: stride,
      points: const [38.2946, 51.6963, 73.5318, 51.5014, 41.5493, 92.3655, 70.7299, 92.2041],
    );
    expect(rgb.length, kAlignedFaceSize * kAlignedFaceSize * 3);
    for (final (u, v) in [(0, 0), (56, 56), (111, 3), (20, 100)]) {
      final o = (v * kAlignedFaceSize + u) * 3;
      expect(rgb[o], closeTo(u, 1), reason: 'red at ($u, $v)');
      expect(rgb[o + 1], closeTo(v, 1), reason: 'green at ($u, $v)');
      expect(rgb[o + 2], 7);
    }
  });

  test('meanDirection is normalised and cosine of a unit vector with itself is 1', () {
    final a = Float32List.fromList([1, 0, 0]);
    final b = Float32List.fromList([0, 1, 0]);
    final m = meanDirection([a, b]);
    expect(cosine(m, m), closeTo(1, 1e-6));
    expect(cosine(m, a), closeTo(math.sqrt1_2, 1e-6));
  });
}
