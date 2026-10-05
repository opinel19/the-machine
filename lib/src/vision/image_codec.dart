import 'dart:typed_data';
import 'dart:ui' as ui;

import 'camera_frame.dart';

/// Interleaved RGB to RGBA with an opaque alpha channel.
Uint8List rgbToRgba(Uint8List rgb) {
  final rgba = Uint8List(rgb.length ~/ 3 * 4);
  for (var i = 0, o = 0; i < rgb.length; i += 3, o += 4) {
    rgba[o] = rgb[i];
    rgba[o + 1] = rgb[i + 1];
    rgba[o + 2] = rgb[i + 2];
    rgba[o + 3] = 255;
  }
  return rgba;
}

Future<ui.Image> imageFromPixels(
  Uint8List pixels,
  int width,
  int height, {
  ui.PixelFormat format = ui.PixelFormat.rgba8888,
  int? rowBytes,
  int? targetWidth,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    rowBytes: rowBytes,
    pixelFormat: format,
  );
  final codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}

Future<Uint8List> encodePng(Uint8List rgba, int width, int height) async {
  final image = await imageFromPixels(rgba, width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// The upright frame as an image, optionally scaled down to [maxWidth].
Future<ui.Image> imageFromFrame(CameraFrame frame, {int? maxWidth}) {
  final size = frame.size;
  if (!frame.nv21) {
    return imageFromPixels(
      frame.bytes,
      frame.width,
      frame.height,
      format: ui.PixelFormat.bgra8888,
      rowBytes: frame.bytesPerRow,
      targetWidth: maxWidth != null && maxWidth < frame.width ? maxWidth : null,
    );
  }
  final width = maxWidth != null && maxWidth < size.width ? maxWidth : size.width.round();
  final height = (width * size.height / size.width).round();
  return imageFromPixels(frame.regionRgba(ui.Offset.zero & size, width, height), width, height);
}
