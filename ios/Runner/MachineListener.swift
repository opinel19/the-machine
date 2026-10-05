import AVFoundation
import Flutter
import Speech

/// Listens for one spoken question and reports it to Dart as `onSpeech`
/// calls on the native channel: `level` (microphone, 0-1) and `partial`
/// text while the user talks, then `final` text once they pause.
final class MachineListener {
  /// A pause this long after the last word ends the question.
  private static let pause: TimeInterval = 1.4
  /// Giving up when nobody says anything, and the longest question.
  private static let waitForSpeech: TimeInterval = 7
  private static let longest: TimeInterval = 15

  private let channel: FlutterMethodChannel
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var tapped = false
  private var silence: Timer?
  private var deadline: Timer?
  private var heard = ""
  private var lastLevelAt: CFTimeInterval = 0

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  var listening: Bool { request != nil }

  func listen(locale: String, result: @escaping FlutterResult) {
    finish(report: false)
    requestAccess { granted in
      guard granted else {
        result(FlutterError(code: "denied", message: "Microphone or speech recognition access denied", details: nil))
        return
      }
      do {
        try self.start(locale: locale)
        result(true)
      } catch {
        self.finish(report: false)
        result(FlutterError(code: "unavailable", message: error.localizedDescription, details: nil))
      }
    }
  }

  /// Stops listening; what was heard so far goes to Dart as `final`.
  func stop() {
    finish(report: true)
  }

  private func requestAccess(_ done: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async { done(false) }
        return
      }
      let reply: (Bool) -> Void = { granted in DispatchQueue.main.async { done(granted) } }
      if #available(iOS 17.0, *) {
        AVAudioApplication.requestRecordPermission(completionHandler: reply)
      } else {
        AVAudioSession.sharedInstance().requestRecordPermission(reply)
      }
    }
  }

  private func start(locale: String) throws {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
      throw ListenerError.unavailable
    }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    // On the phone when it can: faster, and the question stays private.
    if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw ListenerError.noMicrophone }
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      request.append(buffer)
      self?.meter(buffer)
    }
    tapped = true
    engine.prepare()
    try engine.start()

    self.request = request
    heard = ""
    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      DispatchQueue.main.async { self?.recognized(result, error: error, for: request) }
    }
    silence = Timer.scheduledTimer(withTimeInterval: Self.waitForSpeech, repeats: false) { [weak self] _ in
      self?.stop()
    }
    deadline = Timer.scheduledTimer(withTimeInterval: Self.longest, repeats: false) { [weak self] _ in
      self?.stop()
    }
  }

  private func recognized(_ result: SFSpeechRecognitionResult?, error: Error?, for request: SFSpeechAudioBufferRecognitionRequest) {
    // A late answer about an earlier question.
    guard request === self.request else { return }
    guard let result else {
      if error != nil { stop() }
      return
    }
    heard = result.bestTranscription.formattedString
    send(["type": "partial", "text": heard])
    if result.isFinal {
      stop()
      return
    }
    silence?.invalidate()
    silence = Timer.scheduledTimer(withTimeInterval: Self.pause, repeats: false) { [weak self] _ in
      self?.stop()
    }
  }

  private func finish(report: Bool) {
    silence?.invalidate()
    silence = nil
    deadline?.invalidate()
    deadline = nil
    if engine.isRunning { engine.stop() }
    if tapped {
      engine.inputNode.removeTap(onBus: 0)
      tapped = false
    }
    let wasListening = request != nil
    request?.endAudio()
    task?.cancel()
    request = nil
    task = nil
    if report { send(["type": "final", "text": heard]) }
    heard = ""
    if wasListening {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  /// Microphone level for the meter, about 20 times a second.
  private func meter(_ buffer: AVAudioPCMBuffer) {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
    let now = CACurrentMediaTime()
    guard now - lastLevelAt > 0.05 else { return }
    lastLevelAt = now
    var sum: Float = 0
    for i in 0..<Int(buffer.frameLength) {
      sum += samples[i] * samples[i]
    }
    let decibels = 20 * log10(max(sqrt(sum / Float(buffer.frameLength)), 1e-6))
    let level = Double(min(max((decibels + 55) / 45, 0), 1))
    DispatchQueue.main.async { self.send(["type": "level", "level": level]) }
  }

  private func send(_ event: [String: Any]) {
    channel.invokeMethod("onSpeech", arguments: event)
  }

  enum ListenerError: LocalizedError {
    case unavailable
    case noMicrophone

    var errorDescription: String? {
      switch self {
      case .unavailable: return "Speech recognition is not available for this language"
      case .noMicrophone: return "No microphone"
      }
    }
  }
}
