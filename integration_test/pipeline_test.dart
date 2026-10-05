import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:person_of_interest/src/machine/thing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:person_of_interest/src/vision/body.dart';
import 'package:person_of_interest/src/vision/camera_frame.dart';
import 'package:person_of_interest/src/vision/face_embedder.dart';
import 'package:person_of_interest/src/vision/landmarks.dart';

import 'test_faces.dart';

/// Runs photos through the app's real recognition path on a device: frames
/// in the camera's native format (NV21 turned sideways on Android, upright
/// BGRA on iOS) -> ML Kit -> landmarks -> alignment -> native embedder.
///
///     flutter test integration_test -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Clockwise rotation the fake sensor frames need, like a portrait phone.
  final rotation = Platform.isAndroid ? 90 : 0;

  Future<(Uint8List rgba, int width, int height, int stride)> decode(String base64) async {
    final codec = await ui.instantiateImageCodec(base64Decode(base64));
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    // Even sizes keep NV21's 2x2 chroma blocks simple.
    return (data!.buffer.asUint8List(), image.width & ~1, image.height & ~1, image.width * 4);
  }

  /// The upright photo as the camera would deliver it.
  CameraFrame toFrame(Uint8List rgba, int width, int height, int stride) {
    if (!Platform.isAndroid) {
      final bgra = Uint8List(stride * height);
      for (var i = 0; i < stride * height; i += 4) {
        bgra[i] = rgba[i + 2];
        bgra[i + 1] = rgba[i + 1];
        bgra[i + 2] = rgba[i];
        bgra[i + 3] = 255;
      }
      return CameraFrame.bgra(bytes: bgra, width: width, height: height, bytesPerRow: stride);
    }
    // Raw sensor buffer that must turn 90° clockwise to be upright.
    final rw = height, rh = width;
    final nv21 = Uint8List(rw * rh * 3 ~/ 2);
    for (var y = 0; y < rh; y++) {
      for (var x = 0; x < rw; x++) {
        final u = rh - 1 - y, v = x;
        final p = v * stride + u * 4;
        final r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
        nv21[y * rw + x] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        if (x.isEven && y.isEven) {
          final uv = rw * rh + (y >> 1) * rw + x;
          nv21[uv] = (0.5 * r - 0.4187 * g - 0.0813 * b + 128).round().clamp(0, 255);
          nv21[uv + 1] = (-0.1687 * r - 0.3313 * g + 0.5 * b + 128).round().clamp(0, 255);
        }
      }
    }
    return CameraFrame.nv21(bytes: nv21, width: rw, height: rh, bytesPerRow: rw, rotation: rotation);
  }

  testWidgets('the same person matches and a stranger does not', (tester) async {
    final detector = FaceDetector(options: FaceDetectorOptions(enableLandmarks: true));
    final embedder = FaceEmbedder();
    await embedder.load();

    Future<Float32List> embed(String jpeg) async {
      final (rgba, width, height, stride) = await decode(jpeg);
      final frame = toFrame(rgba, width, height, stride);
      final faces = await detector.processImage(
        InputImage.fromBytes(
          bytes: frame.bytes,
          metadata: InputImageMetadata(
            size: Size(frame.width.toDouble(), frame.height.toDouble()),
            rotation: InputImageRotationValue.fromRawValue(rotation)!,
            format: frame.nv21 ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
            bytesPerRow: frame.bytesPerRow,
          ),
        ),
      );
      expect(faces, isNotEmpty, reason: 'ML Kit found no face');
      faces.sort((a, b) => (b.boundingBox.width).compareTo(a.boundingBox.width));
      final face = faces.first;
      // Coordinates must be upright: the face sits inside the upright image.
      expect(Offset.zero & frame.size, isA<Rect>().having((r) => r.contains(face.boundingBox.center), 'contains', true));
      final points = alignmentPointsOf(face);
      expect(points, isNotNull, reason: 'no eye landmarks');
      return embedder.embed(frame.align(points!));
    }

    await tester.runAsync(() async {
      final obama = await embed(obamaJpeg);
      final obama2 = await embed(obama2Jpeg);
      final obama3 = await embed(obama3Jpeg);
      final biden = await embed(bidenJpeg);
      final same = [cosine(obama, obama2), cosine(obama, obama3), cosine(obama2, obama3)];
      final different = [cosine(obama, biden), cosine(obama2, biden), cosine(obama3, biden)];
      debugPrint('[pipeline] rotation=$rotation same=$same different=$different');
      for (final s in same) {
        expect(s, greaterThan(0.5));
      }
      for (final d in different) {
        expect(d, lessThan(0.3));
      }
    });
    await detector.close();
  });

  testWidgets('cars and planes are recognised as such', (tester) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load('assets/models/vehicles.tflite');
      final file = File('${(await getTemporaryDirectory()).path}/vehicles_test.tflite');
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final detector = ObjectDetector(
        options: LocalObjectDetectorOptions(
          mode: DetectionMode.single,
          modelPath: file.path,
          classifyObjects: true,
          multipleObjects: true,
          maximumLabelsPerObject: 3,
          confidenceThreshold: 0.25,
        ),
      );
      Future<Set<ThingKind>> kinds(String jpeg) async {
        final (rgba, width, height, stride) = await decode(jpeg);
        final frame = toFrame(rgba, width, height, stride);
        final objects = await detector.processImage(
          InputImage.fromBytes(
            bytes: frame.bytes,
            metadata: InputImageMetadata(
              size: Size(frame.width.toDouble(), frame.height.toDouble()),
              rotation: InputImageRotationValue.fromRawValue(rotation)!,
              format: frame.nv21 ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
              bytesPerRow: frame.bytesPerRow,
            ),
          ),
        );
        debugPrint('[pipeline] ${[for (final o in objects) o.labels.map((l) => '${l.text}:${l.confidence.toStringAsFixed(2)}').join('/')]}');
        return {
          for (final o in objects)
            for (final l in o.labels) ?ThingKind.ofLabel(l.text),
        };
      }

      expect(await kinds(carJpeg), contains(ThingKind.vehicle));
      expect(await kinds(planeJpeg), contains(ThingKind.aircraft));
      await detector.close();
    });
  });

  testWidgets('people facing away are found, head and all', (tester) async {
    await tester.runAsync(() async {
      final humans = HumanDetector();
      Future<(List<Person>, Size)> people(String jpeg) async {
        final (rgba, width, height, stride) = await decode(jpeg);
        final frame = toFrame(rgba, width, height, stride);
        final found = await humans.detect(frame);
        debugPrint('[pipeline] people: ${[for (final p in found) '${p.body} head ${p.head}']}');
        return (found, frame.size);
      }

      final (man, size) = await people(rearManJpeg);
      expect(man, hasLength(1));
      // His head is at the top middle of the picture.
      expect(man.single.head.center.dx, closeTo(size.width / 2, size.width * 0.1));
      expect(man.single.head.center.dy, lessThan(size.height * 0.25));
      expect((await people(rearWalkerJpeg)).$1, isNotEmpty);
      expect((await people(rearCrowdJpeg)).$1.length, greaterThanOrEqualTo(2));
    });
  });
}
