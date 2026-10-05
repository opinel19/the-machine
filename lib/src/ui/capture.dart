import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../machine/machine_controller.dart';
import '../platform/location_service.dart';
import '../storage/settings.dart';
import '../theme.dart';
import 'box_painter.dart';
import 'camera_feed.dart';
import 'enhance.dart';
import 'hud.dart';

/// Renders what the screen shows, minus the controls, into a PNG: the
/// latest camera frame (filtered, zoomed and cropped like the preview), the
/// overlay captured from [overlay], and a timestamp.
Future<Uint8List?> composeCapture({
  required MachineController controller,
  required EnhanceState enhance,
  required RenderRepaintBoundary overlay,
  required Size view,
  required double pixelRatio,
}) async {
  final frameSize = controller.frameSize;
  final frame = await controller.frameImage();
  if (frame == null || frameSize == null) return null;
  final ratio = math.min(pixelRatio, 2.5);
  final marks = await overlay.toImage(pixelRatio: ratio);
  final settings = controller.settings;
  final theme = settings.theme;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  final bounds = Offset.zero & view;
  canvas
    ..save()
    ..clipRect(bounds);
  if (controller.mirrorOverlay) {
    canvas
      ..translate(view.width, 0)
      ..scale(-1, 1);
  }
  final mapping = FrameMapping(frameSize, view, zoom: enhance.zoom, pan: enhance.pan);
  canvas.drawColor(Colors.black, BlendMode.src);
  if (controller.night) canvas.saveLayer(bounds, Paint()..colorFilter = FeedFilters.nightBoost);
  canvas.drawImageRect(
    frame,
    Offset.zero & Size(frame.width.toDouble(), frame.height.toDouble()),
    mapping.rect(Offset.zero & frameSize),
    Paint()
      ..colorFilter = FeedFilters.of(settings)
      ..filterQuality = FilterQuality.medium,
  );
  if (controller.night) canvas.restore();
  canvas.restore();
  FeedTexturePainter(scanlines: settings.mode == MachineMode.machine && settings.machineVision).paint(canvas, view);
  canvas.drawImageRect(
    marks,
    Offset.zero & Size(marks.width.toDouble(), marks.height.toDouble()),
    bounds,
    Paint()..filterQuality = FilterQuality.medium,
  );

  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final stamp =
      '${now.year}.${two(now.month)}.${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  final title = theme.isSamaritan ? 'SAMARITAN' : 'THE MACHINE';
  final painter = TextPainter(
    text: TextSpan(
      children: [
        TextSpan(text: '$title\n', style: theme.style(size: 13, color: theme.accent, spacing: theme.spacing * 2)),
        TextSpan(
          text: [
            controller.feed.label,
            stamp,
            if (controller.location.position case final p?) formatCoordinates(p.latitude, p.longitude),
            ?controller.location.place,
          ].join('\n'),
          style: theme.style(size: 10, color: theme.dim),
        ),
      ],
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, Offset(16, view.height - painter.height - 24));
  painter.dispose();

  final picture = recorder.endRecording();
  final image = await picture.toImage((view.width * ratio).round(), (view.height * ratio).round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  for (final disposable in [frame, marks, image]) {
    disposable.dispose();
  }
  picture.dispose();
  return data?.buffer.asUint8List();
}
