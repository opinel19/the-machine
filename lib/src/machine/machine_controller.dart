import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/location_service.dart';
import '../platform/machine_native.dart';
import '../storage/identity_store.dart';
import '../storage/number_log.dart';
import '../storage/settings.dart';
import '../vision/body.dart';
import '../vision/camera_frame.dart';
import '../vision/face_align.dart';
import '../vision/face_embedder.dart';
import '../vision/image_codec.dart';
import '../vision/landmarks.dart';
import 'designation.dart';
import 'diagnostics.dart';
import 'enrollment.dart';
import 'events.dart';
import 'feed.dart';
import 'oracle.dart';
import 'people_tracker.dart';
import 'simulation.dart';
import 'ssn.dart';
import 'subject.dart';
import 'thing.dart';
import 'verification.dart';

export '../platform/machine_native.dart' show SpeechEvent;
export 'feed.dart';

/// The number the Machine most recently gave out.
class IssuedNumber {
  const IssuedNumber(this.ssn, this.subjectCode, this.issuedMs);

  final String ssn;
  final String subjectCode;
  final int issuedMs;
}

/// Owns the camera and turns its frames into classified [Subject]s: ML Kit
/// finds and tracks faces, the Core ML embedder tells who they are. Also runs
/// the Machine's side effects: the event log, voice, alerts, numbers, admin
/// verification and recording.
class MachineController extends ChangeNotifier {
  MachineController({required this.identities, required this.settings}) {
    identities.addListener(_reclassifyAll);
    settings.addListener(_onSettingsChanged);
  }

  /// Subjects linger this long after their face was last detected, which
  /// rides out the odd frame where ML Kit misses them.
  static const _subjectTimeoutMs = 600;

  /// A face needs this many embeddings before it gets a verdict.
  static const _samplesBeforeVerdict = 2;

  /// A matched face keeps its identity until it drops this far below the
  /// threshold, so it does not flicker at the boundary.
  static const _hysteresis = 0.06;

  /// Faces that never offer a usable view are called irrelevant after this.
  static const _giveUpMs = 1500;
  static const _maxEmbeddingsPerFrame = 2;
  static const _minFaceWidth = 48.0;

  /// Faces moving faster than this, in face widths per frame, are smeared.
  static const _maxMotion = 0.12;

  /// Aligned faces below this sharpness are too blurred to recognise.
  static const minSharpness = 60.0;

  /// Admin samples this far above the threshold may refine the profile.
  static const _learnMargin = 0.12;
  static const _learnIntervalMs = 15000;
  static const _greetIntervalMs = 120000;
  static const _alertVoiceIntervalMs = 20000;
  static const _verificationTimeoutMs = 10000;

  /// An extra scan must be at least this close to the profile it extends.
  static const _extendMinSimilarity = 0.25;

  /// Scene brightness (0-255) below which night mode engages, and above which
  /// (with the boosted exposure) it lets go again.
  static const _nightOn = 55.0;
  static const _nightOff = 160.0;
  static const _nightExposure = 1.5;
  static const _maxEnrolledSamples = 75;

  final IdentityStore identities;
  final MachineSettings settings;
  final native = MachineNative();
  final events = EventLog();
  final numbers = NumberLog();
  final location = LocationService();
  String? _announcedPlace;
  final _oracle = Oracle();

  /// A number's person counts as seen again after this long out of view.
  static const _resurfaceMs = 30000;

  final _embedder = FaceEmbedder();
  final _humans = HumanDetector();
  final _clock = Stopwatch()..start();
  final _messages = StreamController<String>.broadcast();
  final _alerts = StreamController<Designation>.broadcast();
  final _crashes = StreamController<void>.broadcast();
  Timer? _crashTimer;
  final _subjects = <int, Subject>{};
  final _things = <int, Thing>{};
  ObjectDetector? _objectDetector;
  int _frameIndex = 0;
  int _nextThingId = 0;
  final _diagnostics = Diagnostics();
  final _random = math.Random();
  final _greetedMs = <String, int>{};
  final _learnedMs = <String, int>{};

  FaceDetector? _detector;
  String? _detectorOptions;
  Map<Feed, CameraDescription> _feeds = const {};
  Feed _feed = Feed.rear;
  DeviceOrientation _captureOrientation = DeviceOrientation.portraitUp;
  bool _openLongRange = false;
  Future<void> _cameraOps = Future<void>.value();
  int _nextSubjectNumber = 1000 + math.Random().nextInt(8000);
  int _nextSubjectId = 0;
  int _lastAlertVoiceMs = -1 << 30;
  bool _busy = false;
  bool _disposed = false;
  int _framesInWindow = 0;
  int _windowStartMs = 0;

  /// The live camera, or null while it is closed or being switched.
  final ValueNotifier<CameraController?> camera = ValueNotifier(null);

  /// Size of the upright camera frames in pixels.
  Size? frameSize;

  /// The latest processed frame, for snapshots and the enhance effect.
  CameraFrame? lastFrame;

  String? cameraError;

  /// Null while the recognition model is loading.
  bool? recognitionOnline;
  bool storageLoaded = false;
  double processingFps = 0;
  Enrollment? enrollment;
  AdminVerification? verification;
  IssuedNumber? issuedNumber;

  /// Dark scene: exposure is boosted and dim faces are brightened.
  bool night = false;
  double sceneBrightness = 128;
  int _lastBrightnessMs = -1 << 30;
  int? _recordingSinceMs;

  Feed get feed => _feed;
  bool get canSwitchCamera => _feeds.length > 1;
  /// Vehicles, boats and aircraft in view.
  Iterable<Thing> get things => _things.values;

  /// Faces in view, without ghosts found in the dark.
  Iterable<Subject> get subjects => _subjects.values.where((s) => !s.ghost);
  int get nowMs => _clock.elapsedMilliseconds;

  /// Front camera frames on Android are not mirrored, unlike its preview.
  bool get mirrorOverlay => Platform.isAndroid && _feed == Feed.front;

  /// Approximate focal length of the current feed in frame pixels.
  double get focalPixels => (frameSize?.shortestSide ?? 720) * (_feed == Feed.tele ? 3.9 : 1.3);

  int get adminsInView => _subjects.values.where((s) => s.displayDesignation == Designation.admin).length;

  bool get recording => _recordingSinceMs != null;
  Duration get recordingElapsed => Duration(milliseconds: nowMs - (_recordingSinceMs ?? nowMs));

  /// Short status lines for the user ("SUBJ-4821 FLAGGED AS RELEVANT").
  Stream<String> get messages => _messages.stream;

  /// Designations of subjects that just triggered an alert.
  Stream<Designation> get alerts => _alerts.stream;

  /// The system "crashing" and rebooting (an effect only).
  Stream<void> get crashes => _crashes.stream;

  void triggerCrash() {
    if (_disposed) return;
    events.add(EventKind.alert, 'SYSTEM FAILURE');
    _crashes.add(null);
    unawaited(native.playSound('assets/sounds/alert.wav'));
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (!_disposed) events.add(EventKind.system, 'SYSTEM RESTORED');
    });
  }

  /// With random crashes on, one comes every 4 to 10 minutes.
  void _scheduleCrash() {
    _crashTimer?.cancel();
    if (!settings.crashes || _disposed) return;
    _crashTimer = Timer(Duration(seconds: 240 + _random.nextInt(360)), () {
      if (enrollment == null && verification == null) triggerCrash();
      _scheduleCrash();
    });
  }

  Future<void> start() async {
    await Future.wait([identities.load(), settings.load(), numbers.load(), Diagnostics.init()]);
    if (MachineMode.values.asNameMap()[Diagnostics.mode] case final mode?) settings.overrideMode(mode);
    storageLoaded = true;
    events.add(EventKind.system, 'SYSTEM ONLINE');
    _notify();

    try {
      await _embedder.load();
      recognitionOnline = true;
    } on Object catch (e) {
      debugPrint('Face embedder failed to load: $e');
      recognitionOnline = false;
    }
    _notify();

    unawaited(_prepareObjectDetector());
    try {
      _feeds = _discoverFeeds(await availableCameras());
    } on CameraException catch (e) {
      cameraError = _describe(e);
      _notify();
      return;
    }
    if (_feeds.isEmpty) {
      cameraError = 'NO CAMERA FOUND';
      _notify();
      return;
    }
    final requested = Feed.values.asNameMap()[Diagnostics.feed];
    _feed = _feeds.containsKey(requested)
        ? requested!
        : _feeds.containsKey(Feed.rear)
        ? Feed.rear
        : _feeds.keys.first;
    await _enqueue(() => _open(_feed));
    // After the camera, so the permission prompts come one at a time.
    location.addListener(_onLocation);
    if (settings.location) unawaited(location.start());
  }

  void _onLocation() {
    final place = location.place;
    if (place != null && place != _announcedPlace) {
      _announcedPlace = place;
      events.add(EventKind.system, 'LOCATION: $place');
    }
    _notify();
  }

  /// Rear, then telephoto (if the phone has one), then front, then rear.
  Future<void> switchCamera() {
    const order = [Feed.rear, Feed.tele, Feed.front];
    var next = _feed;
    do {
      next = order[(order.indexOf(next) + 1) % order.length];
    } while (!_feeds.containsKey(next));
    events.add(EventKind.system, 'SWITCHING TO ${next.label}');
    return _enqueue(() => _reopen(next));
  }

  /// Releases the camera, e.g. while the app is in the background.
  Future<void> pause() {
    if (recording) unawaited(toggleRecording());
    return _enqueue(_close);
  }

  Future<void> resume() => _enqueue(() => _open(_feed));

  // --- Designations ------------------------------------------------------------

  /// Flags the subject as relevant, or clears whatever flag it has.
  Future<void> toggleRelevant(int subjectId) async {
    final subject = _subjects[subjectId];
    if (subject == null) return;
    await designate(subjectId, _flaggedIdentity(subject) != null ? Designation.irrelevant : Designation.relevant);
  }

  /// Gives the subject a designation and remembers their face with it;
  /// [Designation.irrelevant] forgets them again.
  Future<void> designate(int subjectId, Designation designation) async {
    final subject = _subjects[subjectId];
    if (subject == null) return;
    if (subject.designation == Designation.admin || subject.designation == Designation.verifying) {
      _say('ADMIN CANNOT BE RECLASSIFIED');
      return;
    }
    final mode = settings.mode;
    final flagged = _flaggedIdentity(subject);
    if (designation == Designation.irrelevant) {
      if (flagged == null) return;
      await identities.remove(flagged);
      subject
        ..identity = null
        ..designation = Designation.irrelevant
        ..announced = Designation.irrelevant;
      final text = '${subject.code} MARKED ${Designation.irrelevant.label(mode)}';
      _say(text);
      events.add(EventKind.info, text);
      _notify();
      return;
    }
    if (flagged != null) {
      subject.identity = await identities.update(flagged, designation: designation);
    } else if (subject.embeddings.isEmpty) {
      _say(subject.rear ? '${subject.code}: FACE NOT VISIBLE' : 'STILL ANALYZING ${subject.code}');
      return;
    } else if (_resemblingAdmin(subject) case final admin?) {
      // Probably an admin seen badly (blur, angle); flagging would teach the
      // list their face.
      _say('${subject.code} RESEMBLES ADMIN ${admin.displayName}');
      return;
    } else {
      final face = subject.lastFace;
      subject.identity = await identities.add(
        designation,
        List.of(subject.embeddings),
        thumbnailPng: face == null ? null : await encodePng(rgbToRgba(face), kAlignedFaceSize, kAlignedFaceSize),
      );
    }
    subject
      ..designation = designation
      ..announced = null;
    _say('${subject.code} FLAGGED AS ${designation.label(mode)}');
    unawaited(HapticFeedback.mediumImpact());
    _notify();
  }

  Future<void> renameIdentity(Identity identity, String name) async {
    final renamed = await identities.update(identity, name: name);
    events.add(EventKind.info, '${identity.displayName} IS NOW ${renamed.displayName}');
  }

  /// Makes [identity] easier (negative) or harder (positive) to match.
  Future<void> setThresholdOffset(Identity identity, double offset) =>
      identities.update(identity, thresholdOffset: offset);

  Future<void> redesignate(Identity identity, Designation designation) =>
      identities.update(identity, designation: designation);

  Future<void> deleteIdentity(Identity identity) async {
    await identities.remove(identity);
    final kind = identity.designation == Designation.admin ? 'ADMIN' : 'PROFILE';
    _say('$kind ${identity.displayName} DELETED');
    events.add(EventKind.system, '$kind ${identity.displayName} DELETED');
  }

  // --- Admin enrollment --------------------------------------------------------

  /// Scans a face for a new admin called [name], a fresh scan for the
  /// existing admin profile [replacing], or an extra look (glasses, a mask)
  /// for [extending].
  Future<void> startEnrollment({required String name, Identity? replacing, Identity? extending}) async {
    if (enrollment != null) return;
    if (recognitionOnline != true) {
      _say('FACIAL RECOGNITION OFFLINE');
      return;
    }
    enrollment = Enrollment(
      returnTo: _feed,
      name: IdentityStore.normalizeName(name),
      replacing: replacing,
      extending: extending,
    );
    for (final s in _subjects.values) {
      s.reset();
    }
    _notify();
    if (_feed != Feed.front && _feeds.containsKey(Feed.front)) {
      await _enqueue(() => _reopen(Feed.front));
    }
  }

  Future<void> cancelEnrollment() async {
    final e = enrollment;
    if (e == null) return;
    enrollment = null;
    _notify();
    if (_feed != e.returnTo) await _enqueue(() => _reopen(e.returnTo));
  }

  Future<void> _enroll(Enrollment e, CameraFrame frame, int now) async {
    final visible = [
      for (final s in subjects)
        if (s.lastSeenMs == now && !s.rear) s,
    ];
    if (visible.isEmpty) {
      e.hint = EnrollmentHint.noFace;
      return;
    }
    if (visible.length > 1) {
      e.hint = EnrollmentHint.multipleFaces;
      return;
    }
    final subject = visible.single;
    final points = subject.alignPoints;
    if (subject.box.width < frame.size.width * 0.22) {
      e.hint = EnrollmentHint.moveCloser;
      return;
    }
    if (points == null || subject.yaw.abs() > 35 || subject.pitch.abs() > 25) {
      e.hint = EnrollmentHint.faceCamera;
      return;
    }
    if (subject.motion > _maxMotion) {
      e.hint = EnrollmentHint.holdStill;
      return;
    }
    if (!e.readyForSample(now)) return;
    final face = frame.align(points);
    final sharpness = faceSharpness(face, scale: alignmentScale(points));
    if (sharpness < _minSharpness) {
      e.hint = EnrollmentHint.holdStill;
      return;
    }
    e.hint = EnrollmentHint.scanning;

    final embedding = await _timedEmbed(_prepareFace(face));
    if (enrollment != e) return;
    e
      ..add(embedding, now)
      ..offerFace(face, sharpness);
    if (!e.complete) return;

    if (!e.consistent) {
      e.samples.clear();
      _say('SCAN INCONSISTENT. RESTARTING');
      return;
    }

    final samples = List.of(e.samples);
    final threshold = settings.threshold;
    final replacing = e.replacing;
    final extending = e.extending;
    final best = e.bestFace;
    if (extending != null) {
      // Glasses or a mask lower the similarity, but it must still plausibly
      // be the same person.
      if (cosine(meanDirection(samples), extending.centroid) < _extendMinSimilarity) {
        e.samples.clear();
        _say('THIS IS NOT ${extending.displayName}. RESTARTING');
        return;
      }
      final all = [...extending.embeddings, ...samples];
      final stored = await identities.update(
        extending,
        embeddings: all.sublist(math.max(0, all.length - _maxEnrolledSamples)),
        keepLearned: true,
      );
      e
        ..result = 'NEW LOOK ADDED TO ${stored.displayName}.'
        ..finished = true;
      events.add(EventKind.admin, 'PROFILE ${stored.displayName} EXTENDED');
      _finishEnrollment(e);
      return;
    }
    final png = best == null ? null : await encodePng(rgbToRgba(best), kAlignedFaceSize, kAlignedFaceSize);
    // One face, one profile: a face that is already an admin updates that
    // profile instead of creating a second one.
    final known = identities.bestMatch(meanDirection(samples), where: _isAdmin, excluding: replacing);
    final Identity stored;
    if (known != null && known.similarity >= threshold) {
      if (replacing != null) {
        e.samples.clear();
        _say('THIS FACE IS ${known.identity.displayName}. RESTARTING');
        return;
      }
      stored = await identities.update(known.identity, embeddings: samples, thumbnailPng: png);
      e.result = 'ALREADY KNOWN AS ${stored.displayName}. PROFILE UPDATED.';
    } else if (replacing != null) {
      stored = await identities.update(replacing, embeddings: samples, thumbnailPng: png);
      e.result = 'PROFILE UPDATED. HELLO, ${stored.displayName}.';
    } else {
      stored = await identities.add(Designation.admin, samples, name: e.name, thumbnailPng: png);
      e.result = 'HELLO, ${stored.displayName}.';
    }
    // An admin is never also on the flagged list.
    for (final designation in Designation.assignable) {
      await identities.removeLookalikes(designation, stored.centroid, threshold);
    }
    e.finished = true;
    events.add(EventKind.admin, 'ADMIN ${stored.displayName} ENROLLED');
    _finishEnrollment(e);
  }

  void _finishEnrollment(Enrollment e) {
    _notify();
    unawaited(HapticFeedback.heavyImpact());
    // Keep the confirmation up while the Machine recognises its new admin,
    // and stay on this camera so the admin can see it happen.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 2600), () {
        if (enrollment != e) return;
        enrollment = null;
        _notify();
      }),
    );
  }

  // --- The Number ---------------------------------------------------------------

  /// Picks an irrelevant subject in view and gives out their number, like
  /// the Machine calling a payphone.
  Future<void> issueNumber() async {
    if (settings.mode == MachineMode.samaritan) return;
    final now = nowMs;
    final candidates = [
      for (final s in subjects)
        if (now - s.lastSeenMs < 300 && s.displayDesignation == Designation.irrelevant) s,
    ];
    if (candidates.isEmpty) {
      _say('NO IRRELEVANT SUBJECTS IN VIEW');
      return;
    }
    final subject = candidates[_random.nextInt(candidates.length)];
    final ssn = randomSsn(_random);
    subject
      ..issuedNumber = ssn
      ..announced = Designation.personOfInterest;
    issuedNumber = IssuedNumber(ssn, subject.code, now);
    events.add(EventKind.number, 'NUMBER ISSUED: $ssn');
    final face = subject.lastFace;
    unawaited(
      numbers.add(
        NumberRecord(
          ssn: ssn,
          issuedAt: DateTime.now(),
          subjectCode: subject.code,
          signature: subject.signature,
          facePng: face == null ? null : await encodePng(rgbToRgba(face), kAlignedFaceSize, kAlignedFaceSize),
          latitude: location.position?.latitude,
          longitude: location.position?.longitude,
          place: location.place,
        ),
      ),
    );
    unawaited(HapticFeedback.heavyImpact());
    unawaited(native.playSound('assets/sounds/ring.wav'));
    _notify();
    if (!settings.voice) return;
    await Future<void>.delayed(const Duration(milliseconds: 4300));
    const digitWords = ['Zero', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'];
    await native.speak([for (final c in ssn.replaceAll('-', '').split('')) digitWords[int.parse(c)]], cutUp: true);
  }

  // --- Conversation -------------------------------------------------------------

  /// Answers a typed question in the current system's voice.
  OracleAnswer ask(String question) {
    final now = nowMs;
    final inView = [
      for (final s in subjects)
        if (now - s.lastSeenMs < 500) s,
    ];
    final answer = _oracle.answer(
      question,
      OracleContext(
        mode: settings.mode,
        adminsInView: [
          for (final s in inView)
            if (s.displayDesignation == Designation.admin) s.identity?.displayName ?? 'ADMIN',
        ],
        subjectsInView: inView.length,
        threatsInView: inView.where((s) => isThreat(s.displayDesignation)).length,
        adminCount: identities.admins.length,
        now: DateTime.now(),
        place: location.place,
        coordinates: switch (location.position) {
          final p? => formatCoordinates(p.latitude, p.longitude, digits: 4),
          null => null,
        },
      ),
    );
    events.add(EventKind.info, 'QUERY: ${question.trim().toUpperCase()}');
    speakLine(answer.text);
    if (answer.issueNumber) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 2500), issueNumber));
    }
    return answer;
  }

  /// Says [text] in the current system's voice: the Machine's spliced
  /// words, or Samaritan's one calm voice. False when the voice is off.
  bool speakLine(String text) {
    if (!settings.voice) return false;
    final samaritan = settings.mode == MachineMode.samaritan;
    unawaited(native.speak(samaritan ? [text] : text.split(' '), cutUp: !samaritan));
    return true;
  }

  /// Microphone level and recognised text while listening, and the end of
  /// everything the voice says.
  Stream<SpeechEvent> get speech => native.speechEvents;

  /// Listens for one spoken question in the chosen language. Returns why it
  /// cannot (`denied`, `unavailable`), or null once listening.
  Future<String?> listen() async {
    await native.stopSpeaking();
    return native.listen(settings.talkLocale);
  }

  Future<void> stopListening() => native.stopListening();

  // --- Simulation ---------------------------------------------------------------

  /// Who "run a simulation" is about when nobody was tapped: a threat in
  /// view, else a number, else anyone. Null means the user.
  Subject? simulationTarget() {
    final now = nowMs;
    final inView = [
      for (final s in subjects)
        if (now - s.lastSeenMs < 500) s,
    ];
    return inView.where((s) => isThreat(s.displayDesignation)).firstOrNull ??
        inView.where((s) => s.displayDesignation == Designation.personOfInterest).firstOrNull ??
        inView.firstOrNull;
  }

  void simulationStarted(String subject) => events.add(EventKind.info, 'SIMULATING $subject');

  /// Logs the verdict and says it.
  void reportSimulation(SimulationPlan plan) {
    events.add(EventKind.info, 'SIMULATION ${plan.subject}: ${plan.metric} ${plan.percent}%');
    speakLine('${plan.metric.toLowerCase()}: ${plan.percent}%.');
  }

  // --- Admin verification -----------------------------------------------------

  /// With the admin lock on, resolves true once an admin shows their face
  /// (switching to the front camera if needed) or the device owner
  /// authenticates.
  Future<bool> verifyAdmin() async {
    if (!settings.adminLock || identities.admins.isEmpty || _adminInView()) return true;
    final pending = verification;
    if (pending != null) return pending.result;

    final v = verification = AdminVerification(deadlineMs: nowMs + _verificationTimeoutMs);
    final returnTo = _feed;
    _notify();
    Timer(const Duration(milliseconds: _verificationTimeoutMs), () {
      if (v.done) return;
      v.denied = true;
      _notify();
    });
    if (_feed != Feed.front && _feeds.containsKey(Feed.front)) {
      unawaited(_enqueue(() => _reopen(Feed.front)));
    }
    final granted = await v.result;
    verification = null;
    events.add(granted ? EventKind.admin : EventKind.alert, granted ? 'ADMIN VERIFIED' : 'ACCESS DENIED');
    _notify();
    if (_feed != returnTo) unawaited(_enqueue(() => _reopen(returnTo)));
    return granted;
  }

  void cancelVerification() => verification?.complete(false);

  Future<void> verifyWithPasscode() async {
    final v = verification;
    if (v == null) return;
    if (await native.authenticate('Unlock The Machine')) v.complete(true);
  }

  bool _adminInView() {
    final now = nowMs;
    return _subjects.values.any((s) => s.displayDesignation == Designation.admin && !s.rear && now - s.lastSeenMs < 300);
  }

  // --- Capture ------------------------------------------------------------------

  Future<void> toggleRecording() async {
    if (!native.supportsRecording) {
      _say('USE THE SYSTEM SCREEN RECORDER');
      return;
    }
    if (recording) {
      _recordingSinceMs = null;
      _notify();
      final saved = await native.stopRecording();
      _say(saved ? 'RECORDING SAVED TO PHOTOS' : 'RECORDING NOT SAVED');
      events.add(EventKind.system, saved ? 'RECORDING SAVED' : 'RECORDING LOST');
    } else if (await native.startRecording()) {
      _recordingSinceMs = nowMs;
      events.add(EventKind.system, 'RECORDING');
      _notify();
    } else {
      _say('RECORDING UNAVAILABLE');
    }
  }

  /// The latest frame as an image, optionally scaled down to [maxWidth].
  Future<ui.Image?> frameImage({int? maxWidth}) async {
    final frame = lastFrame;
    return frame == null ? null : imageFromFrame(frame, maxWidth: maxWidth);
  }

  Future<void> saveCapture(Uint8List png) async {
    final saved = await native.saveImage(png);
    _say(saved ? 'IMAGE CAPTURED' : 'CAPTURE FAILED. ALLOW PHOTO ACCESS IN SETTINGS');
    events.add(EventKind.system, saved ? 'IMAGE CAPTURED' : 'CAPTURE FAILED');
  }

  // --- Frame processing ---------------------------------------------------------

  void _onFrame(CameraController source, CameraImage image) {
    if (_busy || _disposed || source != camera.value) return;
    _busy = true;
    _process(source, image)
        .catchError((Object e, StackTrace stack) => debugPrint('Frame processing failed: $e\n$stack'))
        .whenComplete(() => _busy = false);
  }

  Future<void> _process(CameraController source, CameraImage image) async {
    final startUs = _clock.elapsedMicroseconds;
    final frame = CameraFrame.fromCameraImage(image, rotation: _frameRotation(source));
    final plane = image.planes.first;
    final input = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(frame.rotation) ?? InputImageRotation.rotation0deg,
        format: frame.nv21 ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    final pass = _frameIndex++ % 3;
    // ML Kit starts on the faces first; people are looked for meanwhile.
    final findingFaces = _ensureDetector().processImage(input);
    final findingPeople = settings.bodies && enrollment == null && pass == 1 ? _humans.detect(frame) : null;
    final faces = await findingFaces;
    final people = findingPeople == null ? null : await findingPeople;
    if (_disposed || source != camera.value) return;
    final detectUs = _clock.elapsedMicroseconds - startUs;
    final objects = _objectDetector;
    if (settings.vehicles && objects != null && pass == 0) {
      final found = await objects.processImage(input);
      if (_disposed || source != camera.value) return;
      _trackThings(found, nowMs);
    } else if (!settings.vehicles && _things.isNotEmpty) {
      _things.clear();
    }

    final now = nowMs;
    frameSize = frame.size;
    lastFrame = frame;
    _track(faces, now);
    if (people != null) {
      trackPeople(_subjects, people, now, () => Subject(id: _nextSubjectId++, number: _takeSubjectNumber(), firstSeenMs: now));
    }
    _checkLight(frame, now);
    _updateNight(frame, now);
    final e = enrollment;
    if (e != null && !e.finished) {
      await _enroll(e, frame, now);
    } else if (recognitionOnline ?? false) {
      await _recognize(frame, now);
    }
    if (_disposed || source != camera.value) return;
    _announce(now);
    final v = verification;
    if (v != null && !v.done && _adminInView()) v.complete(true);
    _diagnostics.frame(detectUs: detectUs, totalUs: _clock.elapsedMicroseconds - startUs);
    _diagnostics.tick(now, subjects: _subjects.length, camera: _feed.name);
    _countFrame(now);
    _notify();
  }

  FaceDetector _ensureDetector() {
    final key = '${settings.liveness}/${settings.longRange}';
    final current = _detector;
    if (current != null && key == _detectorOptions) return current;
    current?.close();
    _detectorOptions = key;
    return _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableTracking: true,
        enableClassification: settings.liveness,
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: settings.longRange ? 0.04 : 0.08,
      ),
    );
  }

  void _track(List<Face> faces, int now) {
    final unmatched = <Face>[];
    for (final face in faces) {
      final subject = _subjectTrackedAs(face.trackingId);
      if (subject == null) {
        unmatched.add(face);
      } else {
        _observe(subject, face, now);
      }
    }
    for (final face in unmatched) {
      // ML Kit hands out a new tracking id when it loses a face and finds it
      // again. A lingering subject at the same spot keeps its identity, but
      // gets re-checked right away in case it is someone else.
      var subject = _reacquire(face.boundingBox, now);
      if (subject != null) {
        subject.lastEmbeddingMs = -1 << 30;
      } else {
        subject = Subject(id: _nextSubjectId++, number: _takeSubjectNumber(), firstSeenMs: now);
        _subjects[subject.id] = subject;
      }
      subject.trackingId = face.trackingId;
      _observe(subject, face, now);
    }
    final expired = [
      for (final s in _subjects.values)
        if (now - s.lastSeenMs > _subjectTimeoutMs) s,
    ];
    for (final s in expired) {
      _subjects.remove(s.id);
      if (s.announced == Designation.admin) {
        events.add(EventKind.admin, 'ADMIN ${s.identity?.displayName ?? ''} OUT OF VIEW');
      }
    }
    // A blink turns a verifying admin into a verified one.
    for (final s in _subjects.values) {
      if (s.designation == Designation.verifying && s.live) _classify(s);
    }
  }

  /// Marks faces found in near-black, flat pixels as ghosts: ML Kit sees
  /// faces in the noise of a covered lens.
  void _checkLight(CameraFrame frame, int now) {
    for (final s in _subjects.values) {
      if (s.rear || s.lastSeenMs != now || now - s.lastLightCheckMs < 500) continue;
      s.lastLightCheckMs = now;
      final rgba = frame.regionRgba(s.box, 8, 8);
      var sum = 0.0, sumSq = 0.0;
      for (var i = 0; i < rgba.length; i += 4) {
        final luma = rgba[i] * 0.299 + rgba[i + 1] * 0.587 + rgba[i + 2] * 0.114;
        sum += luma;
        sumSq += luma * luma;
      }
      const n = 64;
      final mean = sum / n;
      final spread = math.sqrt(math.max(0, sumSq / n - mean * mean));
      s.ghost = mean < 14 && spread < 8;
      if (s.ghost) _diagnostics.skip('dark');
    }
  }

  void _updateNight(CameraFrame frame, int now) {
    if (now - _lastBrightnessMs < 1000) return;
    _lastBrightnessMs = now;
    final rgba = frame.regionRgba(Offset.zero & frame.size, 16, 16);
    var sum = 0.0;
    for (var i = 0; i < rgba.length; i += 4) {
      sum += rgba[i] * 0.299 + rgba[i + 1] * 0.587 + rgba[i + 2] * 0.114;
    }
    sceneBrightness = sum / 256;
    final dark = settings.nightMode && (night ? sceneBrightness < _nightOff : sceneBrightness < _nightOn);
    if (dark == night) return;
    night = dark;
    events.add(EventKind.system, night ? 'NIGHT MODE ENGAGED' : 'NIGHT MODE OFF');
    unawaited(_enqueue(_applyExposure));
  }

  Future<void> _applyExposure() async {
    final controller = camera.value;
    if (controller == null) return;
    final max = await controller.getMaxExposureOffset();
    await controller.setExposureOffset(night ? math.min(max, _nightExposure) : 0);
  }

  /// The aligned face as the embedder should see it: dim faces are lifted.
  Uint8List _prepareFace(Uint8List face) => settings.nightMode ? brightenFace(face) : face;

  double get _minSharpness => night ? minSharpness * 0.66 : minSharpness;

  /// ML Kit needs the classifier as a file on disk.
  Future<void> _prepareObjectDetector() async {
    try {
      const asset = 'assets/models/vehicles.tflite';
      final data = await rootBundle.load(asset);
      final file = File('${(await getApplicationSupportDirectory()).path}/vehicles.tflite');
      if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      _objectDetector = ObjectDetector(
        options: LocalObjectDetectorOptions(
          mode: DetectionMode.stream,
          modelPath: file.path,
          classifyObjects: true,
          multipleObjects: true,
          maximumLabelsPerObject: 3,
          confidenceThreshold: 0.25,
        ),
      );
    } on Object catch (e) {
      debugPrint('Vehicle detection unavailable: $e');
    }
  }

  void _trackThings(List<DetectedObject> found, int now) {
    for (final object in found) {
      ThingKind? kind;
      String? label;
      for (final l in object.labels) {
        kind = ThingKind.ofLabel(l.text);
        if (kind != null) {
          label = l.text.toUpperCase();
          break;
        }
      }
      final id = object.trackingId;
      final existing = id == null ? null : _things[id];
      if (kind == null || label == null) {
        // Keep an already classified thing through a frame of doubt.
        if (existing != null) {
          existing
            ..box = object.boundingBox
            ..lastSeenMs = now;
        }
        continue;
      }
      final key = id ?? -(++_nextThingId);
      final thing = _things.putIfAbsent(key, () {
        final code = _thingCode(kind!);
        events.add(EventKind.info, '${kind.label} ACQUIRED: $label');
        return Thing(id: key, kind: kind, label: label!, code: code, firstSeenMs: now);
      });
      thing
        ..kind = kind
        ..label = label
        ..box = object.boundingBox
        ..lastSeenMs = now;
    }
    _things.removeWhere((_, t) => now - t.lastSeenMs > 1200);
  }

  /// Licence plate, hull number or flight number, made up.
  String _thingCode(ThingKind kind) {
    const letters = 'ABCDEFGHJKLMNPRSTUVWXYZ';
    String l() => letters[_random.nextInt(letters.length)];
    String d(int n) => List.generate(n, (_) => _random.nextInt(10)).join();
    return switch (kind) {
      ThingKind.vehicle => '${d(1)}${l()}${l()}${l()}${d(3)}',
      ThingKind.watercraft => 'HULL ${l()}${l()}-${d(4)}',
      ThingKind.aircraft => '${const ['UA', 'AA', 'DL', 'TK', 'BA', 'LH'][_random.nextInt(6)]} ${d(4)}',
    };
  }

  Subject? _subjectTrackedAs(int? trackingId) {
    if (trackingId == null) return null;
    for (final s in _subjects.values) {
      if (s.trackingId == trackingId) return s;
    }
    return null;
  }

  /// The not-yet-matched subject whose last box overlaps [box] the most. A
  /// person seen from behind only has an estimated head, so a face turning
  /// up anywhere on it counts.
  Subject? _reacquire(Rect box, int now) {
    Subject? best;
    var bestOverlap = 0.25;
    for (final s in _subjects.values) {
      if (s.lastSeenMs == now) continue;
      final onHead = s.rear && s.box.inflate(s.box.width * 0.5).contains(box.center);
      final overlap = onHead ? math.max(0.3, iou(s.box, box)) : iou(s.box, box);
      if (overlap > bestOverlap) {
        best = s;
        bestOverlap = overlap;
      }
    }
    return best;
  }

  static void _observe(Subject subject, Face face, int now) {
    subject.observe(face.boundingBox, now);
    subject
      ..rear = false
      ..yaw = face.headEulerAngleY ?? 0
      ..pitch = face.headEulerAngleX ?? 0
      ..alignPoints = alignmentPointsOf(face);
    final left = face.leftEyeOpenProbability, right = face.rightEyeOpenProbability;
    subject.eyesOpen = left != null && right != null ? (left + right) / 2 : null;
    subject.blink.add(subject.eyesOpen, now);
  }

  Future<void> _recognize(CameraFrame frame, int now) async {
    final due = <Subject>[];
    for (final s in _subjects.values) {
      if (s.ghost || s.rear || s.lastSeenMs != now || now - s.lastEmbeddingMs < s.embeddingIntervalMs) continue;
      final reason = s.alignPoints == null
          ? 'landmarks'
          : s.box.width < _minFaceWidth
          ? 'small'
          : s.yaw.abs() > 40 || s.pitch.abs() > 30
          ? 'pose'
          : s.motion > _maxMotion
          ? 'motion'
          : null;
      if (reason == null) {
        due.add(s);
      } else {
        _diagnostics.skip(reason);
      }
    }
    due.sort((a, b) => a.embeddings.length.compareTo(b.embeddings.length));

    for (final subject in due.take(_maxEmbeddingsPerFrame)) {
      final points = subject.alignPoints!;
      final face = frame.align(points);
      subject.sharpness = faceSharpness(face, scale: alignmentScale(points));
      _diagnostics.sharpness(subject.sharpness);
      // Too blurred to trust; try again on the next frame.
      if (subject.sharpness < _minSharpness) {
        _diagnostics.skip('blur');
        continue;
      }
      final embedding = await _timedEmbed(_prepareFace(face));
      subject
        ..lastFace = face
        ..addEmbedding(embedding, now);
      _classify(subject);
      _learn(subject, embedding, now);
      _trackNumber(subject);
    }
    for (final s in _subjects.values) {
      if (s.designation == Designation.analyzing && s.embeddings.isEmpty && now - s.firstSeenMs > _giveUpMs) {
        s.designation = Designation.irrelevant;
      }
    }
  }

  Future<Float32List> _timedEmbed(Uint8List face) async {
    final startUs = _clock.elapsedMicroseconds;
    final embedding = await _embedder.embed(face);
    _diagnostics.embed(_clock.elapsedMicroseconds - startUs);
    return embedding;
  }

  void _classify(Subject subject) {
    final signature = subject.signature;
    if (signature == null || subject.embeddings.length < _samplesBeforeVerdict) return;

    // A face keeps its current identity until it drops a little below the
    // threshold, so the verdict does not flicker at the boundary.
    bool passes(IdentityMatch? m) =>
        m != null &&
        m.similarity >=
            settings.threshold +
                m.identity.thresholdOffset -
                (identical(m.identity, subject.identity) ? _hysteresis : 0);

    // Admins outrank everyone on the flagged list.
    final admin = identities.bestMatch(signature, where: _isAdmin);
    final flagged = identities.bestMatch(signature, where: _isFlagged);
    final match = passes(admin)
        ? admin
        : passes(flagged)
        ? flagged
        : null;

    var designation = match?.identity.designation ?? Designation.irrelevant;
    if (designation == Designation.admin && settings.liveness && !subject.live) {
      designation = Designation.verifying;
    }
    subject
      ..identity = match?.identity
      ..designation = designation
      ..similarity = match?.similarity ?? math.max(admin?.similarity ?? 0, flagged?.similarity ?? 0);
  }

  /// Links a face to a number given out earlier: the box shows the number
  /// again and the log counts the sighting.
  void _trackNumber(Subject subject) {
    final signature = subject.signature;
    if (signature == null || subject.embeddings.length < _samplesBeforeVerdict) return;
    final issued = subject.issuedNumber;
    NumberRecord? record;
    if (issued != null) {
      record = numbers.records.where((r) => r.ssn == issued).firstOrNull;
      if (record != null && record.signature == null) {
        record.signature = signature;
        unawaited(numbers.save());
      }
    } else {
      var best = settings.threshold;
      for (final r in numbers.records) {
        final known = r.signature;
        if (known == null) continue;
        final similarity = cosine(signature, known);
        if (similarity >= best) {
          best = similarity;
          record = r;
        }
      }
      if (record == null) return;
      subject.issuedNumber = record.ssn;
    }
    if (record == null) return;
    final now = DateTime.now();
    if (issued == null && now.difference(record.lastSeenAt).inMilliseconds > _resurfaceMs) {
      record.sightings++;
      events.add(EventKind.number, 'NUMBER ${record.ssn} RESURFACED');
    }
    record.lastSeenAt = now;
    final here = location.position;
    if (here != null) {
      record
        ..lastLatitude = here.latitude
        ..lastLongitude = here.longitude;
    }
    if (issued == null) unawaited(numbers.save());
  }

  /// Folds confident, new-looking views of an admin into their profile.
  void _learn(Subject subject, Float32List embedding, int now) {
    final admin = subject.identity;
    if (!settings.learning || subject.designation != Designation.admin || admin == null) return;
    final threshold = settings.threshold;
    if (subject.similarity < threshold + _learnMargin) return;
    if (now - (_learnedMs[admin.id] ?? -_learnIntervalMs) < _learnIntervalMs) return;
    if (cosine(embedding, admin.centroid) < threshold + 0.05) return;
    // Only views unlike anything stored teach the profile something.
    var closest = -1.0;
    for (final sample in admin.samples) {
      closest = math.max(closest, cosine(embedding, sample));
    }
    if (closest > 0.9) return;
    _learnedMs[admin.id] = now;
    subject.identity = identities.learn(admin, embedding);
    events.add(EventKind.admin, 'PROFILE ${admin.displayName} REFINED');
  }

  /// Logs, greets and alerts once per settled change of verdict.
  void _announce(int now) {
    final mode = settings.mode;
    for (final s in _subjects.values) {
      final d = s.displayDesignation;
      if (!d.settled || d == s.announced) continue;
      s.announced = d;
      final who = s.identity?.displayName ?? s.code;
      switch (d) {
        case Designation.admin:
          events.add(EventKind.admin, '${d.label(mode)} $who ACQUIRED');
          _greet(s.identity!, now);
        case Designation.relevant || Designation.threat:
          events.add(EventKind.alert, '${d.label(mode)} $who DETECTED');
          _alert(d, now);
        case Designation.perpetrator:
          events.add(EventKind.alert, '${d.label(mode)} $who IN VIEW');
        case Designation.asset || Designation.analogInterface || Designation.catalyst:
          events.add(EventKind.info, '${d.label(mode)} $who ACQUIRED');
        default:
          break;
      }
    }
  }

  void _greet(Identity admin, int now) {
    if (!settings.voice) return;
    final last = _greetedMs[admin.id];
    if (last != null && now - last < _greetIntervalMs) return;
    _greetedMs[admin.id] = now;
    if (settings.mode == MachineMode.samaritan) {
      unawaited(native.speak(['Priority target acquired.'], cutUp: false));
      return;
    }
    final name = admin.displayName.startsWith('ADMIN ') ? 'Admin' : _titleCase(admin.displayName);
    unawaited(native.speak(['Hello,', ...name.split(' ')], cutUp: true));
  }

  void _alert(Designation designation, int now) {
    if (settings.alerts) {
      _alerts.add(designation);
      unawaited(HapticFeedback.heavyImpact());
    }
    if (settings.voice && now - _lastAlertVoiceMs > _alertVoiceIntervalMs) {
      _lastAlertVoiceMs = now;
      final samaritan = settings.mode == MachineMode.samaritan;
      final words = samaritan || designation == Designation.threat
          ? ['Threat', 'detected.']
          : ['Relevant', 'subject', 'detected.'];
      unawaited(native.speak(samaritan ? [words.join(' ')] : words, cutUp: !samaritan));
    } else if (settings.alerts) {
      unawaited(native.playSound('assets/sounds/alert.wav'));
    }
  }

  void _reclassifyAll() {
    for (final s in _subjects.values) {
      _classify(s);
    }
    _notify();
  }

  void _onSettingsChanged() {
    final retrying = settings.location && location.unavailable;
    if (storageLoaded && settings.location != location.running && !retrying) {
      settings.location ? unawaited(location.start()) : location.stop();
    }
    if (settings.crashes != (_crashTimer?.isActive ?? false)) _scheduleCrash();
    if (!settings.nightMode && night) {
      night = false;
      unawaited(_enqueue(_applyExposure));
    }
    if (camera.value != null && settings.longRange != _openLongRange) {
      unawaited(_enqueue(() => _reopen(_feed)));
    }
    _reclassifyAll();
  }

  static bool _isAdmin(Identity i) => i.designation == Designation.admin;

  static bool _isFlagged(Identity i) => i.designation != Designation.admin;

  static Identity? _flaggedIdentity(Subject subject) {
    final identity = subject.identity;
    return identity != null && identity.designation != Designation.admin ? identity : null;
  }

  /// The admin this subject's face comes close to, if any.
  Identity? _resemblingAdmin(Subject subject) {
    final signature = subject.signature;
    if (signature == null) return null;
    final admin = identities.bestMatch(signature, where: _isAdmin);
    return admin != null && admin.similarity >= settings.threshold - 0.1 ? admin.identity : null;
  }

  // --- Camera lifecycle ---------------------------------------------------------

  /// Runs camera operations one after another so they never overlap.
  Future<void> _enqueue(Future<void> Function() op) {
    return _cameraOps = _cameraOps.then((_) async {
      try {
        await op();
      } on CameraException catch (e) {
        cameraError = _describe(e);
        _notify();
      } on Object catch (e, stack) {
        // Keep the queue alive whatever happens.
        debugPrint('Camera operation failed: $e\n$stack');
      }
    });
  }

  Future<void> _reopen(Feed feed) async {
    await _close();
    await _open(feed);
  }

  Future<void> _open(Feed feed) async {
    if (_disposed || camera.value != null || _feeds.isEmpty) return;
    final description = _feeds[feed] ?? _feeds.values.first;
    final longRange = settings.longRange;
    final controller = CameraController(
      description,
      longRange ? ResolutionPreset.veryHigh : ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
      // Frames follow the interface: portrait or either landscape.
      await controller.lockCaptureOrientation(_captureOrientation);
    } on Object {
      await controller.dispose();
      rethrow;
    }
    if (_disposed) {
      await controller.dispose();
      return;
    }
    _feed = _feeds.entries.firstWhere((e) => e.value == description).key;
    _things.clear();
    _openLongRange = longRange;
    _subjects.clear();
    final preview = controller.value.previewSize;
    final landscape =
        _captureOrientation == DeviceOrientation.landscapeLeft ||
        _captureOrientation == DeviceOrientation.landscapeRight;
    frameSize = preview == null
        ? null
        : landscape
        ? Size(preview.longestSide, preview.shortestSide)
        : Size(preview.shortestSide, preview.longestSide);
    lastFrame = null;
    cameraError = null;
    controller.addListener(() => _onCameraValue(controller));
    camera.value = controller;
    _notify();
    await controller.startImageStream((image) => _onFrame(controller, image));
    if (night) await _applyExposure();
  }

  Future<void> _close() async {
    final controller = camera.value;
    if (controller == null) return;
    camera.value = null;
    _subjects.clear();
    _notify();
    // Let the preview leave the widget tree before its texture goes away
    // (no frames are produced while the app is in the background).
    if (SchedulerBinding.instance.framesEnabled) await SchedulerBinding.instance.endOfFrame;
    try {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
    } on CameraException catch (e) {
      debugPrint('Stopping image stream failed: $e');
    }
    await controller.dispose();
  }

  /// Follows the phone into portrait or landscape (not upside down, which the
  /// interface does not support either).
  void _onCameraValue(CameraController controller) {
    if (controller != camera.value) return;
    final orientation = controller.value.deviceOrientation;
    if (orientation == DeviceOrientation.portraitDown || orientation == _captureOrientation) return;
    _captureOrientation = orientation;
    unawaited(
      _enqueue(() async {
        if (controller == camera.value) await controller.lockCaptureOrientation(orientation);
      }),
    );
  }

  /// Clockwise rotation that makes this camera's frames upright (Android).
  int _frameRotation(CameraController controller) {
    if (!Platform.isAndroid) return 0;
    const turns = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final device = turns[_captureOrientation] ?? 0;
    final sensor = controller.description.sensorOrientation;
    return controller.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
  }

  static Map<Feed, CameraDescription> _discoverFeeds(List<CameraDescription> cameras) {
    CameraDescription? pick(CameraLensDirection direction, bool Function(CameraLensType type) accept) {
      for (final c in cameras) {
        if (c.lensDirection == direction && accept(c.lensType)) return c;
      }
      return null;
    }

    final rear =
        pick(CameraLensDirection.back, (t) => t == CameraLensType.wide || t == CameraLensType.unknown) ??
        pick(CameraLensDirection.back, (_) => true);
    final tele = pick(CameraLensDirection.back, (t) => t == CameraLensType.telephoto);
    final front = pick(CameraLensDirection.front, (_) => true);
    return {Feed.rear: ?rear, Feed.tele: ?tele, Feed.front: ?front};
  }

  // --- Helpers ------------------------------------------------------------------

  int _takeSubjectNumber() {
    final n = _nextSubjectNumber;
    _nextSubjectNumber = n >= 9999 ? 1000 : n + 1;
    return n;
  }

  static String _titleCase(String name) => name
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  void _countFrame(int now) {
    _framesInWindow++;
    final elapsed = now - _windowStartMs;
    if (elapsed >= 1000) {
      processingFps = _framesInWindow * 1000 / elapsed;
      _framesInWindow = 0;
      _windowStartMs = now;
    }
  }

  void _say(String message) {
    if (!_disposed) _messages.add(message);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _describe(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'CAMERA ACCESS DENIED. ENABLE IT IN SETTINGS > THE MACHINE';
      default:
        return 'CAMERA ERROR: ${e.code}';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    identities.removeListener(_reclassifyAll);
    settings.removeListener(_onSettingsChanged);
    final controller = camera.value;
    camera.value = null;
    controller?.dispose();
    camera.dispose();
    _detector?.close();
    _objectDetector?.close();
    _messages.close();
    _alerts.close();
    _crashTimer?.cancel();
    _crashes.close();
    events.dispose();
    numbers.dispose();
    location
      ..removeListener(_onLocation)
      ..dispose();
    super.dispose();
  }
}
