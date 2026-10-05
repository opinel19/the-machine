import AVFoundation
import Flutter
import LocalAuthentication
import Photos
import ReplayKit
import UIKit

/// Native services for Dart (`poi/native`): the voice and listening, sounds,
/// saving to the photo library, in-app screen recording and device-owner
/// authentication.
final class MachineNativePlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private let listener: MachineListener
  private let speech = AVSpeechSynthesizer()
  private var player: AVAudioPlayer?
  private var lastVoice: String?

  /// Utterances queued or being spoken; Dart hears `spoken` when it drops
  /// back to zero.
  private var utterances = 0

  /// Voices for the Machine's spliced speech: real voices only, none of the
  /// novelty ones (Bells, Bubbles, Zarvox, ...).
  private lazy var voices: [AVSpeechSynthesisVoice] = {
    let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    let real = english.filter { !$0.identifier.contains("speech.synthesis.voice") }
    return real.isEmpty ? english : real
  }()

  init(registrar: FlutterPluginRegistrar, channel: FlutterMethodChannel) {
    self.registrar = registrar
    self.channel = channel
    listener = MachineListener(channel: channel)
    super.init()
    speech.delegate = self
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "poi/native", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(MachineNativePlugin(registrar: registrar, channel: channel), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speak":
      let args = call.arguments as? [String: Any]
      speak(args?["words"] as? [String] ?? [], cutUp: args?["cutUp"] as? Bool ?? true)
      result(nil)
    case "stopSpeaking":
      speech.stopSpeaking(at: .immediate)
      if utterances > 0 {
        utterances = 0
        spoken()
      }
      result(nil)
    case "listen":
      speech.stopSpeaking(at: .immediate)
      listener.listen(locale: call.arguments as? String ?? "en-US", result: result)
    case "stopListening":
      listener.stop()
      result(nil)
    case "playSound":
      playSound(asset: call.arguments as? String)
      result(nil)
    case "stopSound":
      player?.stop()
      result(nil)
    case "saveImage":
      saveImage((call.arguments as? FlutterStandardTypedData)?.data, result: result)
    case "startRecording":
      startRecording(result: result)
    case "stopRecording":
      stopRecording(result: result)
    case "takeLaunchAction":
      result(LaunchAction.take())
    case "authenticate":
      authenticate(reason: call.arguments as? String ?? "Unlock", result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Sound

  /// Plays over other audio and through the mute switch: the user turned the
  /// Machine's voice on.
  private func activateAudio() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
    try? session.setActive(true)
  }

  private func speak(_ words: [String], cutUp: Bool) {
    guard !words.isEmpty, !listener.listening else { return }
    activateAudio()
    if !cutUp {
      let utterance = AVSpeechUtterance(string: words.joined(separator: " "))
      utterance.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? voices.first
      utterance.rate = 0.46
      utterance.pitchMultiplier = 0.9
      utterances += 1
      speech.speak(utterance)
      return
    }
    // Every word in a different voice, like the Machine talking through
    // snippets of recorded people.
    for word in words {
      let utterance = AVSpeechUtterance(string: word)
      var voice = voices.randomElement()
      if voices.count > 1 {
        while voice?.identifier == lastVoice { voice = voices.randomElement() }
      }
      lastVoice = voice?.identifier
      utterance.voice = voice
      utterance.rate = Float.random(in: 0.44...0.54)
      utterance.pitchMultiplier = Float.random(in: 0.88...1.12)
      utterance.postUtteranceDelay = 0.05
      utterances += 1
      speech.speak(utterance)
    }
  }

  private func utteranceEnded() {
    guard utterances > 0 else { return }
    utterances -= 1
    if utterances == 0 { spoken() }
  }

  /// The voice fell silent: tell Dart, and let other apps' audio back up.
  private func spoken() {
    channel.invokeMethod("onSpeech", arguments: ["type": "spoken"])
    if !listener.listening, player?.isPlaying != true {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private func playSound(asset: String?) {
    guard let asset,
      let path = Bundle.main.path(forResource: registrar.lookupKey(forAsset: asset), ofType: nil)
    else { return }
    activateAudio()
    player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
    player?.play()
  }

  // MARK: Photos

  private func withPhotoAccess(_ body: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      body(status == .authorized || status == .limited)
    }
  }

  private func saveImage(_ data: Data?, result: @escaping FlutterResult) {
    guard let data else {
      result(false)
      return
    }
    withPhotoAccess { granted in
      guard granted else {
        DispatchQueue.main.async { result(false) }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
      }) { saved, _ in
        DispatchQueue.main.async { result(saved) }
      }
    }
  }

  // MARK: Screen recording

  private func startRecording(result: @escaping FlutterResult) {
    let recorder = RPScreenRecorder.shared()
    guard recorder.isAvailable else {
      result(false)
      return
    }
    recorder.isMicrophoneEnabled = false
    recorder.startRecording { error in
      DispatchQueue.main.async { result(error == nil) }
    }
  }

  /// Stops recording and saves the clip to the photo library.
  private func stopRecording(result: @escaping FlutterResult) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("machine-\(Int(Date().timeIntervalSince1970)).mp4")
    RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
      guard error == nil else {
        DispatchQueue.main.async { result(false) }
        return
      }
      self.withPhotoAccess { granted in
        guard granted else {
          DispatchQueue.main.async { result(false) }
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }) { saved, _ in
          try? FileManager.default.removeItem(at: url)
          DispatchQueue.main.async { result(saved) }
        }
      }
    }
  }

  // MARK: Authentication

  private func authenticate(reason: String, result: @escaping FlutterResult) {
    let context = LAContext()
    var error: NSError?
    // Without a passcode there is no owner to check, and refusing would lock
    // the user out of their own settings.
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      result(true)
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { granted, _ in
      DispatchQueue.main.async { result(granted) }
    }
  }
}

extension MachineNativePlugin: AVSpeechSynthesizerDelegate {
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { self.utteranceEnded() }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async { self.utteranceEnded() }
  }
}
