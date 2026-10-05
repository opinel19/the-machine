import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';

import 'face_align.dart';

/// One camera frame: BGRA8888 on iOS (already upright), NV21 on Android
/// (as the sensor delivers it, [rotation] degrees clockwise from upright).
///
/// Face coordinates always refer to the upright image of size [size].
class CameraFrame {
  CameraFrame.bgra({required this.bytes, required this.width, required this.height, required this.bytesPerRow})
    : nv21 = false,
      rotation = 0;

  CameraFrame.nv21({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotation,
  }) : nv21 = true;

  factory CameraFrame.fromCameraImage(CameraImage image, {int rotation = 0}) {
    final plane = image.planes.first;
    // Android's plugin hands over NV21 as one plane (some versions label it
    // yuv420); iOS delivers BGRA.
    final nv21 =
        image.format.group == ImageFormatGroup.nv21 ||
        (image.format.group == ImageFormatGroup.yuv420 && image.planes.length == 1);
    return nv21
        ? CameraFrame.nv21(
            bytes: plane.bytes,
            width: image.width,
            height: image.height,
            bytesPerRow: plane.bytesPerRow,
            rotation: rotation,
          )
        : CameraFrame.bgra(bytes: plane.bytes, width: image.width, height: image.height, bytesPerRow: plane.bytesPerRow);
  }

  final Uint8List bytes;

  /// Buffer dimensions as stored.
  final int width;
  final int height;
  final int bytesPerRow;
  final bool nv21;

  /// Clockwise rotation (0, 90, 180 or 270) that makes the buffer upright.
  final int rotation;

  /// Size of the upright image.
  Size get size => rotation % 180 == 0
      ? Size(width.toDouble(), height.toDouble())
      : Size(height.toDouble(), width.toDouble());

  /// Aligned 112x112 RGB face for [points] in upright coordinates.
  Uint8List align(List<double> points) {
    if (!nv21) {
      return alignFace(bgra: bytes, width: width, height: height, bytesPerRow: bytesPerRow, points: points);
    }
    final t = SimilarityTransform.fit(points, alignmentTemplate(points));
    final det = t.a * t.a + t.b * t.b;
    final ia = t.a / det, ib = t.b / det;
    const size = kAlignedFaceSize;
    final out = Uint8List(size * size * 3);
    final rgb = Float64List(3);
    var o = 0;
    for (var v = 0; v < size; v++) {
      for (var u = 0; u < size; u++) {
        final rx = u - t.tx, ry = v - t.ty;
        _sampleUpright(ia * rx + ib * ry, -ib * rx + ia * ry, rgb);
        out[o++] = _byte(rgb[0]);
        out[o++] = _byte(rgb[1]);
        out[o++] = _byte(rgb[2]);
      }
    }
    return out;
  }

  /// RGBA pixels of the upright [region], resampled to [outWidth]x[outHeight].
  /// Pixels outside the frame are black.
  Uint8List regionRgba(Rect region, int outWidth, int outHeight) {
    final out = Uint8List(outWidth * outHeight * 4);
    final rgb = Float64List(3);
    final sx = region.width / outWidth, sy = region.height / outHeight;
    var o = 0;
    for (var j = 0; j < outHeight; j++) {
      final uy = region.top + (j + 0.5) * sy - 0.5;
      for (var i = 0; i < outWidth; i++) {
        _sampleUpright(region.left + (i + 0.5) * sx - 0.5, uy, rgb);
        out[o++] = _byte(rgb[0]);
        out[o++] = _byte(rgb[1]);
        out[o++] = _byte(rgb[2]);
        out[o++] = 255;
      }
    }
    return out;
  }

  static int _byte(double v) => (v + 0.5).toInt().clamp(0, 255);

  /// Bilinear colour at upright position ([ux], [uy]) into [rgb].
  void _sampleUpright(double ux, double uy, Float64List rgb) {
    double x, y;
    switch (rotation) {
      case 90:
        x = uy;
        y = height - 1 - ux;
      case 180:
        x = width - 1 - ux;
        y = height - 1 - uy;
      case 270:
        x = width - 1 - uy;
        y = ux;
      default:
        x = ux;
        y = uy;
    }
    rgb[0] = rgb[1] = rgb[2] = 0;
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    for (var k = 0; k < 4; k++) {
      final xx = x0 + (k & 1), yy = y0 + (k >> 1);
      if (xx < 0 || yy < 0 || xx >= width || yy >= height) continue;
      final w = ((k & 1) == 1 ? fx : 1 - fx) * ((k >> 1) == 1 ? fy : 1 - fy);
      if (w == 0) continue;
      if (nv21) {
        final luma = bytes[yy * bytesPerRow + xx].toDouble();
        final uv = height * bytesPerRow + (yy >> 1) * bytesPerRow + (xx & ~1);
        final cr = bytes[uv] - 128.0, cb = bytes[uv + 1] - 128.0;
        rgb[0] += (luma + 1.402 * cr) * w;
        rgb[1] += (luma - 0.344136 * cb - 0.714136 * cr) * w;
        rgb[2] += (luma + 1.772 * cb) * w;
      } else {
        final p = yy * bytesPerRow + xx * 4;
        rgb[0] += bytes[p + 2] * w;
        rgb[1] += bytes[p + 1] * w;
        rgb[2] += bytes[p] * w;
      }
    }
  }
}
