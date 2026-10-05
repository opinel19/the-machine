import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/vision/camera_frame.dart';
import 'package:person_of_interest/src/vision/face_align.dart';

/// Grey NV21 frame whose luma encodes the raw position: Y = x + 3y.
CameraFrame nv21Frame(int width, int height, int rotation) {
  final bytes = Uint8List(width * height * 3 ~/ 2)..fillRange(width * height, width * height * 3 ~/ 2, 128);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[y * width + x] = x + 3 * y;
    }
  }
  return CameraFrame.nv21(bytes: bytes, width: width, height: height, bytesPerRow: width, rotation: rotation);
}

int lumaAt(Uint8List rgba, int width, int u, int v) => rgba[(v * width + u) * 4];

void main() {
  test('NV21 frames are read upright for every sensor rotation', () {
    const w = 8, h = 6;
    // Raw pixel each upright pixel (u, v) must come from.
    final expectations = <int, (int, int) Function(int u, int v)>{
      0: (u, v) => (u, v),
      90: (u, v) => (v, h - 1 - u),
      180: (u, v) => (w - 1 - u, h - 1 - v),
      270: (u, v) => (w - 1 - v, u),
    };
    expectations.forEach((rotation, raw) {
      final frame = nv21Frame(w, h, rotation);
      final size = frame.size;
      expect(size, rotation % 180 == 0 ? const Size(w * 1.0, h * 1.0) : const Size(h * 1.0, w * 1.0));
      final uw = size.width.toInt(), uh = size.height.toInt();
      final rgba = frame.regionRgba(Offset.zero & size, uw, uh);
      for (var v = 0; v < uh; v++) {
        for (var u = 0; u < uw; u++) {
          final (x, y) = raw(u, v);
          expect(lumaAt(rgba, uw, u, v), x + 3 * y, reason: 'rotation $rotation at ($u, $v)');
        }
      }
    });
  });

  test('BGRA regions come out as RGBA', () {
    const w = 4, h = 2, stride = w * 4 + 8;
    final bytes = Uint8List(stride * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        bytes.setAll(y * stride + x * 4, [10 * x, 100 + y, 200, 255]); // B, G, R, A
      }
    }
    final frame = CameraFrame.bgra(bytes: bytes, width: w, height: h, bytesPerRow: stride);
    final rgba = frame.regionRgba(const Rect.fromLTWH(0, 0, 4, 2), 4, 2);
    expect(rgba.sublist((1 * 4 + 3) * 4, (1 * 4 + 3) * 4 + 4), [200, 101, 30, 255]);
  });

  test('sharpness drops for a blurred face and is scale-compensated', () {
    // A checkerboard is maximally sharp; its box-blurred version is not.
    final sharp = Uint8List(kAlignedFaceSize * kAlignedFaceSize * 3);
    final blurred = Uint8List.fromList(sharp);
    for (var y = 0; y < kAlignedFaceSize; y++) {
      for (var x = 0; x < kAlignedFaceSize; x++) {
        final v = ((x ~/ 4) + (y ~/ 4)).isEven ? 220 : 30;
        sharp.fillRange((y * kAlignedFaceSize + x) * 3, (y * kAlignedFaceSize + x) * 3 + 3, v);
        blurred.fillRange((y * kAlignedFaceSize + x) * 3, (y * kAlignedFaceSize + x) * 3 + 3, 125);
      }
    }
    expect(faceSharpness(sharp), greaterThan(1000));
    expect(faceSharpness(blurred), lessThan(1));
    expect(faceSharpness(sharp, scale: 2), closeTo(faceSharpness(sharp) * 4, 1e-6));
    expect(faceSharpness(sharp, scale: 0.5), faceSharpness(sharp));
  });
}
