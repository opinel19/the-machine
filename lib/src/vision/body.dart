import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_frame.dart';

/// A face-sized box where the head of a person found by body should be, so
/// they get the same mark as a face. A head is about 0.4 of the shoulders'
/// width, and a seventh of a [wholeBody] standing in view; otherwise (an
/// upper body, or someone cut off by the frame) width decides.
Rect headOfBody(Rect body, {bool wholeBody = false}) {
  final headWidth = math.min(body.width * 0.4, body.height * (wholeBody ? 0.14 : 0.45));
  final headHeight = headWidth * 1.2;
  // headSquare() draws 1.3x the face box, 6% higher: undo both.
  final side = headHeight * 1.05 / 1.3;
  final center = Offset(body.center.dx, body.top + headHeight / 2 + side * 0.06);
  return Rect.fromCenter(center: center, width: side * 0.85, height: side);
}

/// Someone found by body, facing the camera or not.
class Person {
  Person(this.body, {bool wholeBody = false}) : head = headOfBody(body, wholeBody: wholeBody);

  /// In upright frame pixels.
  final Rect body;

  /// Where their face would be; see [headOfBody].
  final Rect head;
}

/// Finds people, including ones facing away or too far off for a face:
/// Vision's upper-body detector on iOS, EfficientDet-Lite0 (COCO) on Android.
class HumanDetector {
  static const _channel = MethodChannel('poi/humans');

  /// The Android model's input: a square this many pixels wide.
  static const _side = 320;

  Future<List<Person>> detect(CameraFrame frame) async {
    try {
      return Platform.isAndroid ? await _detectSquare(frame) : await _detectUpperBodies(frame);
    } on PlatformException catch (e) {
      debugPrint('Human detection failed: ${e.message}');
    } on MissingPluginException {
      debugPrint('Human detection is not available');
    }
    return const [];
  }

  /// iOS frames are upright BGRA already.
  Future<List<Person>> _detectUpperBodies(CameraFrame frame) async {
    final flat = await _channel.invokeMethod<Float64List>('detect', {
      'bytes': frame.bytes,
      'width': frame.width,
      'height': frame.height,
      'bytesPerRow': frame.bytesPerRow,
    });
    return [
      if (flat != null)
        for (var i = 0; i + 4 < flat.length; i += 5)
          if (flat[i + 4] >= 0.5) Person(Rect.fromLTWH(flat[i], flat[i + 1], flat[i + 2], flat[i + 3])),
    ];
  }

  /// The frame letterboxed into the model's square, boxes mapped back.
  Future<List<Person>> _detectSquare(CameraFrame frame) async {
    final size = frame.size;
    final square = Rect.fromCenter(center: size.center(Offset.zero), width: size.longestSide, height: size.longestSide);
    final flat = await _channel.invokeMethod<Float64List>('detect', frame.regionRgba(square, _side, _side));
    final people = <Person>[];
    for (var i = 0; flat != null && i + 4 < flat.length; i += 5) {
      final body = Rect.fromLTRB(
        square.left + flat[i] * square.width,
        square.top + flat[i + 1] * square.height,
        square.left + flat[i + 2] * square.width,
        square.top + flat[i + 3] * square.height,
      ).intersect(Offset.zero & size);
      if (body.isEmpty) continue;
      // Someone cut off by the bottom edge is not a whole body.
      people.add(Person(body, wholeBody: body.bottom < size.height * 0.98));
    }
    return people;
  }
}
