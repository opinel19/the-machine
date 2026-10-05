import 'dart:math' as math;
import 'dart:typed_data';

/// Side length, in pixels, of the aligned face crop the embedding model expects.
const int kAlignedFaceSize = 112;

/// Where the eyes and mouth corners sit in the 112x112 ArcFace crop the
/// embedding model was trained on, listed left-to-right as seen in the image.
const List<double> _eyesAndMouthTemplate = <double>[
  38.2946, 51.6963, // eye, image left
  73.5318, 51.5014, // eye, image right
  41.5493, 92.3655, // mouth corner, image left
  70.7299, 92.2041, // mouth corner, image right
];

const List<double> _eyesTemplate = <double>[
  38.2946, 51.6963,
  73.5318, 51.5014,
];

/// Similarity transform `x' = a*x - b*y + tx`, `y' = b*x + a*y + ty`
/// (uniform scale + rotation + translation, no shear or reflection).
class SimilarityTransform {
  const SimilarityTransform(this.a, this.b, this.tx, this.ty);

  /// Least-squares fit mapping the points in [src] onto [dst]. Both are flat
  /// `[x0, y0, x1, y1, ...]` lists of the same length.
  factory SimilarityTransform.fit(List<double> src, List<double> dst) {
    assert(src.length == dst.length && src.length >= 4 && src.length.isEven);
    final n = src.length ~/ 2;
    var sx = 0.0, sy = 0.0, dx = 0.0, dy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += src[2 * i];
      sy += src[2 * i + 1];
      dx += dst[2 * i];
      dy += dst[2 * i + 1];
    }
    sx /= n;
    sy /= n;
    dx /= n;
    dy /= n;

    // Treating points as complex numbers, the optimal scaled rotation is
    // z = sum(conj(p) * q) / sum(|p|^2) over the centred points.
    var dot = 0.0, cross = 0.0, norm = 0.0;
    for (var i = 0; i < n; i++) {
      final px = src[2 * i] - sx, py = src[2 * i + 1] - sy;
      final qx = dst[2 * i] - dx, qy = dst[2 * i + 1] - dy;
      dot += px * qx + py * qy;
      cross += px * qy - py * qx;
      norm += px * px + py * py;
    }
    final a = dot / norm, b = cross / norm;
    return SimilarityTransform(a, b, dx - (a * sx - b * sy), dy - (b * sx + a * sy));
  }

  final double a;
  final double b;
  final double tx;
  final double ty;

  double get scale => math.sqrt(a * a + b * b);
}

/// The template for [points] (see [alignFace]).
List<double> alignmentTemplate(List<double> points) => points.length == 8 ? _eyesAndMouthTemplate : _eyesTemplate;

/// How much [alignFace] enlarges the face described by [points]: above 1 for
/// faces smaller than the 112 px crop.
double alignmentScale(List<double> points) => SimilarityTransform.fit(points, alignmentTemplate(points)).scale;

/// Sharpness of an aligned face: the variance of the Laplacian of its
/// luminance, multiplied by [scale]² when the face was enlarged ([scale] from
/// [alignmentScale]) so small and large faces share one threshold. Crisp
/// faces score above ~120; motion blur of 6-10% of the face width drops it
/// below ~60.
double faceSharpness(Uint8List rgb, {double scale = 1}) {
  const size = kAlignedFaceSize;
  final luma = Float32List(size * size);
  for (var i = 0, p = 0; i < luma.length; i++, p += 3) {
    luma[i] = rgb[p] * 0.299 + rgb[p + 1] * 0.587 + rgb[p + 2] * 0.114;
  }
  var sum = 0.0, sumSq = 0.0;
  for (var y = 1; y < size - 1; y++) {
    for (var x = 1; x < size - 1; x++) {
      final i = y * size + x;
      final lap = luma[i - size] + luma[i + size] + luma[i - 1] + luma[i + 1] - 4 * luma[i];
      sum += lap;
      sumSq += lap * lap;
    }
  }
  const n = (size - 2) * (size - 2);
  final mean = sum / n;
  final enlarge = math.max(scale, 1.0);
  return (sumSq / n - mean * mean) * enlarge * enlarge;
}

/// Warps the face described by [points] out of a BGRA8888 frame onto the
/// ArcFace template and returns 112x112 RGB pixels (row-major, interleaved).
///
/// [points] are image coordinates, ordered left-to-right as they appear in
/// the image: `[eyeL, eyeR]` or `[eyeL, eyeR, mouthL, mouthR]` as flat x/y
/// pairs. Pixels that fall outside the frame are black, like OpenCV's
/// `warpAffine` with a constant border.
Uint8List alignFace({
  required Uint8List bgra,
  required int width,
  required int height,
  required int bytesPerRow,
  required List<double> points,
}) {
  final t = SimilarityTransform.fit(points, alignmentTemplate(points));

  // Invert the transform to find, for every output pixel, where to sample.
  final det = t.a * t.a + t.b * t.b;
  final ia = t.a / det, ib = t.b / det;

  const size = kAlignedFaceSize;
  final out = Uint8List(size * size * 3);
  final maxX = width - 1, maxY = height - 1;
  var o = 0;
  for (var v = 0; v < size; v++) {
    final ry = v - t.ty;
    for (var u = 0; u < size; u++) {
      final rx = u - t.tx;
      final x = ia * rx + ib * ry;
      final y = -ib * rx + ia * ry;

      final x0 = x.floor(), y0 = y.floor();
      final fx = x - x0, fy = y - y0;
      final w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy);
      final w01 = (1 - fx) * fy, w11 = fx * fy;

      var r = 0.0, g = 0.0, b = 0.0;
      if (x0 >= 0 && y0 >= 0 && x0 < maxX && y0 < maxY) {
        final p00 = y0 * bytesPerRow + x0 * 4;
        final p01 = p00 + bytesPerRow;
        b = bgra[p00] * w00 + bgra[p00 + 4] * w10 + bgra[p01] * w01 + bgra[p01 + 4] * w11;
        g = bgra[p00 + 1] * w00 + bgra[p00 + 5] * w10 + bgra[p01 + 1] * w01 + bgra[p01 + 5] * w11;
        r = bgra[p00 + 2] * w00 + bgra[p00 + 6] * w10 + bgra[p01 + 2] * w01 + bgra[p01 + 6] * w11;
      } else if (x0 >= -1 && y0 >= -1 && x0 <= maxX && y0 <= maxY) {
        // Straddling the border: only in-frame neighbours contribute.
        for (var k = 0; k < 4; k++) {
          final xx = x0 + (k & 1), yy = y0 + (k >> 1);
          if (xx < 0 || yy < 0 || xx > maxX || yy > maxY) continue;
          final w = k == 0 ? w00 : k == 1 ? w10 : k == 2 ? w01 : w11;
          final p = yy * bytesPerRow + xx * 4;
          b += bgra[p] * w;
          g += bgra[p + 1] * w;
          r += bgra[p + 2] * w;
        }
      }
      out[o++] = (r + 0.5).toInt().clamp(0, 255);
      out[o++] = (g + 0.5).toInt().clamp(0, 255);
      out[o++] = (b + 0.5).toInt().clamp(0, 255);
    }
  }
  return out;
}

/// Mean luminance (0-255) of an aligned face.
double faceBrightness(Uint8List rgb) {
  var sum = 0.0;
  for (var p = 0; p < rgb.length; p += 3) {
    sum += rgb[p] * 0.299 + rgb[p + 1] * 0.587 + rgb[p + 2] * 0.114;
  }
  return sum / (rgb.length / 3);
}

/// Lifts a dim face: stretches its luminance range to roughly 10-245 with a
/// gentle gamma, keeping colour ratios. Faces that are bright enough are
/// returned unchanged.
Uint8List brightenFace(Uint8List rgb, {double below = 90}) {
  if (faceBrightness(rgb) >= below) return rgb;
  // Robust range: ignore the darkest and brightest 2% of pixels.
  final histogram = List<int>.filled(256, 0);
  final n = rgb.length ~/ 3;
  for (var p = 0; p < rgb.length; p += 3) {
    histogram[(rgb[p] * 0.299 + rgb[p + 1] * 0.587 + rgb[p + 2] * 0.114).round().clamp(0, 255)]++;
  }
  int percentile(double q) {
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += histogram[v];
      if (seen >= q * n) return v;
    }
    return 255;
  }

  final lo = percentile(0.02).toDouble(), hi = math.max(percentile(0.98).toDouble(), lo + 16);
  final lut = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    final t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    lut[v] = (10 + 235 * math.pow(t, 0.8)).round();
  }
  final out = Uint8List(rgb.length);
  for (var p = 0; p < rgb.length; p += 3) {
    final luma = rgb[p] * 0.299 + rgb[p + 1] * 0.587 + rgb[p + 2] * 0.114;
    final gain = luma < 1 ? 1.0 : lut[luma.round().clamp(0, 255)] / luma;
    for (var c = 0; c < 3; c++) {
      out[p + c] = (rgb[p + c] * gain).round().clamp(0, 255);
    }
  }
  return out;
}
