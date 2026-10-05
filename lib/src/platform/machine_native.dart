import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Something the speech recogniser or the voice reported.
class SpeechEvent {
  const SpeechEvent(this.type, {this.text = '', this.level = 0});

  /// `level` (microphone, 0-1), `partial` and `final` (recognised text), or
  /// `spoken` (the voice fell silent).
  final String type;
  final String text;
  final double level;
}

/// Native services: the voice and listening, sounds, saving photos, screen
/// recording and device-owner authentication. Every call degrades to a no-op
/// (or false) when the platform side is missing or fails.
class MachineNative {
  static const _channel = MethodChannel('poi/native');

  final _speech = StreamController<SpeechEvent>.broadcast();
  bool _handlingCalls = false;

  /// In-app screen recording exists on iOS (ReplayKit) only.
  bool get supportsRecording => Platform.isIOS;

  /// Speaks [words]. With [cutUp] every word gets a different voice, like the
  /// Machine talking through spliced recordings; otherwise one calm voice.
  Future<void> speak(List<String> words, {required bool cutUp}) =>
      _call<void>('speak', {'words': words, 'cutUp': cutUp});

  Future<void> stopSpeaking() => _call<void>('stopSpeaking');

  /// Microphone level and recognised text while listening, and the end of
  /// each thing the voice says.
  Stream<SpeechEvent> get speechEvents {
    _handleCalls();
    return _speech.stream;
  }

  /// Starts recognising one spoken question in [locale] (`tr-TR`, `en-US`);
  /// the text arrives as [speechEvents]. Returns null once listening, else
  /// why not: `denied` or `unavailable`.
  Future<String?> listen(String locale) async {
    _handleCalls();
    try {
      await _channel.invokeMethod<bool>('listen', locale);
      return null;
    } on PlatformException catch (e) {
      debugPrint('Native listen failed: ${e.message}');
      return e.code;
    } on MissingPluginException {
      return 'unavailable';
    }
  }

  /// Stops listening; what was heard so far arrives as a `final` event.
  Future<void> stopListening() => _call<void>('stopListening');

  /// Plays a bundled sound, e.g. `assets/sounds/ring.wav`.
  Future<void> playSound(String asset) => _call<void>('playSound', asset);

  Future<void> stopSound() => _call<void>('stopSound');

  /// Saves a PNG to the photo library.
  Future<bool> saveImage(Uint8List png) async => await _call<bool>('saveImage', png) ?? false;

  Future<bool> startRecording() async => await _call<bool>('startRecording') ?? false;

  /// Stops recording and saves the clip to the photo library.
  Future<bool> stopRecording() async => await _call<bool>('stopRecording') ?? false;

  /// What a Siri shortcut, app shortcut or widget asked the app to do once
  /// open (`talk`, `number`), if anything. Reading it clears it.
  Future<String?> takeLaunchAction() => _call<String>('takeLaunchAction');

  /// Face ID / Touch ID / passcode of the device owner.
  Future<bool> authenticate(String reason) async => await _call<bool>('authenticate', reason) ?? false;

  void _handleCalls() {
    if (_handlingCalls) return;
    _handlingCalls = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onSpeech') return;
      final event = (call.arguments as Map).cast<String, Object?>();
      _speech.add(
        SpeechEvent(
          event['type'] as String? ?? '',
          text: event['text'] as String? ?? '',
          level: (event['level'] as num?)?.toDouble() ?? 0,
        ),
      );
    });
  }

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint('Native $method failed: ${e.message}');
    } on MissingPluginException {
      debugPrint('Native $method is not available on this platform');
    }
    return null;
  }
}
