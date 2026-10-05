import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../machine/machine_controller.dart';
import '../storage/settings.dart';
import 'enhance.dart';

/// Colour treatments of the camera feed.
abstract final class FeedFilters {
  /// Mostly desaturated, contrasty and slightly cold: the Machine's footage.
  static const machine = ColorFilter.matrix(<double>[
    0.38098, 0.70032, 0.07070, 0, -25.6, //
    0.21685, 0.90950, 0.07364, 0, -25.6, //
    0.22986, 0.77327, 0.26886, 0, -25.6, //
    0, 0, 0, 1, 0, //
  ]);

  /// Grey, harder contrast and a cold cast: Samaritan's footage.
  static const samaritan = ColorFilter.matrix(<double>[
    0.27638, 0.92976, 0.09386, 0, -38.4, //
    0.27638, 0.92976, 0.09386, 0, -36.0, //
    0.28744, 0.96695, 0.09761, 0, -32.0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Night mode: roughly doubles brightness and lifts the shadows.
  static const nightBoost = ColorFilter.matrix(<double>[
    1.9, 0, 0, 0, 18, //
    0, 1.9, 0, 0, 18, //
    0, 0, 1.9, 0, 18, //
    0, 0, 0, 1, 0, //
  ]);

  static const none = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  static ColorFilter of(MachineSettings settings) {
    if (!settings.machineVision) return none;
    return settings.mode == MachineMode.samaritan ? samaritan : machine;
  }
}

/// The camera preview filling the screen the way [FrameMapping] assumes,
/// filtered for the current mode and zoomed by the enhance effect.
class CameraFeed extends StatelessWidget {
  const CameraFeed({super.key, required this.controller, required this.enhance});

  final MachineController controller;
  final EnhanceState enhance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraController?>(
      valueListenable: controller.camera,
      builder: (context, camera, _) {
        if (camera == null || !camera.value.isInitialized) return const ColoredBox(color: Colors.black);
        return ListenableBuilder(
          listenable: Listenable.merge([controller.settings, enhance, controller]),
          builder: (context, _) {
            final frame = controller.frameSize;
            if (frame == null) return const ColoredBox(color: Colors.black);
            // Upright on both platforms: iOS rotates the frames themselves,
            // Android's plugin rotates (and mirrors) its preview widget.
            final preview = SizedBox(width: frame.width, height: frame.height, child: camera.buildPreview());
            final filtered = ColorFiltered(
              colorFilter: FeedFilters.of(controller.settings),
              child: Transform(
                transform: Matrix4.identity()
                  ..translateByDouble(enhance.pan.dx, enhance.pan.dy, 0, 1)
                  ..scaleByDouble(enhance.zoom, enhance.zoom, 1, 1),
                child: SizedBox.expand(
                  child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: preview),
                ),
              ),
            );
            return controller.night
                ? ColorFiltered(colorFilter: FeedFilters.nightBoost, child: filtered)
                : filtered;
          },
        );
      },
    );
  }
}
