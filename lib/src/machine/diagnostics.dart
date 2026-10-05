import 'package:flutter/services.dart';

/// Launch-time test hooks and per-second pipeline stats.
///
/// Launch with environment variables, e.g.
/// `xcrun devicectl device process launch --console -e '{"POI_DIAG":"1","POI_FEED":"front"}' ...`:
/// `POI_DIAG=1` logs stats through NSLog, `POI_FEED` (rear, tele, front) and
/// `POI_MODE` (machine, samaritan) pick the starting camera and system
/// without changing saved settings.
class Diagnostics {
  static const _channel = MethodChannel('poi/face_embedder');
  static bool enabled = false;
  static String? feed;
  static String? mode;

  static Future<void> init() async {
    try {
      final env = await _channel.invokeMapMethod<String, String>('launchEnvironment') ?? const {};
      enabled = env['POI_DIAG'] == '1';
      feed = env['POI_FEED'];
      mode = env['POI_MODE'];
    } on MissingPluginException {
      enabled = false;
    }
  }

  int _windowStartMs = 0;
  int _frames = 0;
  int _detectUs = 0;
  int _frameUs = 0;
  int _embeds = 0;
  int _embedUs = 0;
  final _skips = <String, int>{};
  double _sharpnessSum = 0;
  int _sharpnessCount = 0;

  void frame({required int detectUs, required int totalUs}) {
    _frames++;
    _detectUs += detectUs;
    _frameUs += totalUs;
  }

  void embed(int us) {
    _embeds++;
    _embedUs += us;
  }

  /// A face that was not embedded this frame, and why.
  void skip(String reason) => _skips[reason] = (_skips[reason] ?? 0) + 1;

  void sharpness(double value) {
    _sharpnessSum += value;
    _sharpnessCount++;
  }

  /// Prints and resets the counters once a second.
  void tick(int nowMs, {required int subjects, required String camera}) {
    final elapsed = nowMs - _windowStartMs;
    if (elapsed < 1000) return;
    if (enabled && _frames > 0) {
      String ms(int us, int n) => n == 0 ? '-' : (us / n / 1000).toStringAsFixed(1);
      final skips = _skips.entries.map((e) => '${e.key}:${e.value}').join(',');
      final sharp = _sharpnessCount == 0 ? '-' : (_sharpnessSum / _sharpnessCount).toStringAsFixed(0);
      _channel.invokeMethod<void>(
        'log',
        '[machine] $camera fps=${(_frames * 1000 / elapsed).toStringAsFixed(1)} '
        'detect=${ms(_detectUs, _frames)}ms frame=${ms(_frameUs, _frames)}ms '
        'embed=${ms(_embedUs, _embeds)}ms x$_embeds subjects=$subjects sharp=$sharp skip=[$skips]',
      );
    }
    _windowStartMs = nowMs;
    _frames = _detectUs = _frameUs = _embeds = _embedUs = _sharpnessCount = 0;
    _sharpnessSum = 0;
    _skips.clear();
  }
}
