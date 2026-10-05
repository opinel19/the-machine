import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../machine/mode.dart';

export '../machine/mode.dart';

/// User-tunable options, persisted on the device.
class MachineSettings extends ChangeNotifier {
  /// Cosine similarity a face needs to be matched to a known identity.
  /// Same-person pairs typically score 0.6-0.9, strangers below 0.25.
  static const defaultThreshold = 0.40;
  static const minThreshold = 0.25;
  static const maxThreshold = 0.70;

  static const _prefix = 'poi.';

  SharedPreferences? _prefs;

  double _threshold = defaultThreshold;
  int _season = 3;
  MachineMode _mode = MachineMode.machine;
  final Map<String, bool> _flags = {
    'showScores': false,
    'machineVision': true,
    'voice': true,
    'eventLog': true,
    'alerts': true,
    'liveness': false,
    'adminLock': false,
    'longRange': false,
    'learning': true,
    'nightMode': true,
    'crashes': false,
    'vehicles': true,
    'location': true,
    'bodies': true,
  };

  /// Language spoken questions are recognised in: the phone's, when the
  /// Machine understands it.
  String _talkLanguage = PlatformDispatcher.instance.locale.languageCode == 'tr' ? 'tr' : 'en';

  double get threshold => _threshold;
  set threshold(double value) {
    _threshold = value.clamp(minThreshold, maxThreshold);
    _prefs?.setDouble('${_prefix}threshold', _threshold);
    notifyListeners();
  }

  MachineMode get mode => _mode;
  set mode(MachineMode value) {
    _mode = value;
    _prefs?.setString('${_prefix}mode', value.name);
    notifyListeners();
  }

  /// Which season's box design the Machine draws: 1, 2 or 3 (seasons 3-5).
  int get season => _season;
  set season(int value) {
    _season = value.clamp(1, 3);
    _prefs?.setInt('${_prefix}season', _season);
    notifyListeners();
  }

  /// Switches system without saving it (test hooks).
  void overrideMode(MachineMode value) {
    _mode = value;
    notifyListeners();
  }

  /// Shows similarity scores and processing rate for tuning.
  bool get showScores => _flag('showScores');
  set showScores(bool v) => _setFlag('showScores', v);

  /// Desaturated, contrasty feed like the show's surveillance footage.
  bool get machineVision => _flag('machineVision');
  set machineVision(bool v) => _setFlag('machineVision', v);

  /// Spoken greetings, alerts and numbers.
  bool get voice => _flag('voice');
  set voice(bool v) => _setFlag('voice', v);

  bool get eventLog => _flag('eventLog');
  set eventLog(bool v) => _setFlag('eventLog', v);

  /// Red flash and vibration when a threat or relevant subject shows up.
  bool get alerts => _flag('alerts');
  set alerts(bool v) => _setFlag('alerts', v);

  /// An admin must blink before being recognised, so a photo will not do.
  bool get liveness => _flag('liveness');
  set liveness(bool v) => _setFlag('liveness', v);

  /// Settings and profiles only open while an admin is in view.
  bool get adminLock => _flag('adminLock');
  set adminLock(bool v) => _setFlag('adminLock', v);

  /// 1080p frames and smaller minimum face size to see faces further away.
  bool get longRange => _flag('longRange');
  set longRange(bool v) => _setFlag('longRange', v);

  /// Admin profiles absorb new views of the face as they are recognised.
  bool get learning => _flag('learning');
  set learning(bool v) => _setFlag('learning', v);

  /// Brightens the feed and dim faces when the scene gets dark.
  bool get nightMode => _flag('nightMode');
  set nightMode(bool v) => _setFlag('nightMode', v);

  /// Now and then the system "crashes" and reboots, like in the show.
  bool get crashes => _flag('crashes');
  set crashes(bool v) => _setFlag('crashes', v);

  /// Boxes for vehicles, boats and aircraft too, like the Machine's feeds.
  bool get vehicles => _flag('vehicles');
  set vehicles(bool v) => _setFlag('vehicles', v);

  /// GPS position and district on the HUD, in captures and in the numbers'
  /// history.
  bool get location => _flag('location');
  set location(bool v) => _setFlag('location', v);

  /// People facing away (or too far for a face) get a box too.
  bool get bodies => _flag('bodies');
  set bodies(bool v) => _setFlag('bodies', v);

  /// `tr` or `en`.
  String get talkLanguage => _talkLanguage;
  set talkLanguage(String value) {
    _talkLanguage = value == 'tr' ? 'tr' : 'en';
    _prefs?.setString('${_prefix}talkLanguage', _talkLanguage);
    notifyListeners();
  }

  /// Locale for the speech recogniser.
  String get talkLocale => _talkLanguage == 'tr' ? 'tr-TR' : 'en-US';

  bool _flag(String key) => _flags[key]!;

  void _setFlag(String key, bool value) {
    _flags[key] = value;
    _prefs?.setBool('$_prefix$key', value);
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _threshold = (prefs.getDouble('${_prefix}threshold') ?? defaultThreshold).clamp(minThreshold, maxThreshold);
    _season = (prefs.getInt('${_prefix}season') ?? 3).clamp(1, 3);
    _mode = MachineMode.values.asNameMap()[prefs.getString('${_prefix}mode')] ?? MachineMode.machine;
    _talkLanguage = prefs.getString('${_prefix}talkLanguage') ?? _talkLanguage;
    for (final key in _flags.keys) {
      final stored = prefs.getBool('$_prefix$key');
      if (stored != null) _flags[key] = stored;
    }
    notifyListeners();
  }
}
