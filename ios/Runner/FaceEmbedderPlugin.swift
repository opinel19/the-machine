import CoreML
import Flutter
import Foundation

/// Runs the bundled Core ML face-embedding model (MobileFaceNet) for Dart.
///
/// `embed` takes an aligned 112x112 face as interleaved RGB bytes and returns
/// its L2-normalised 512-d embedding as a Float32List. Calls are handled on a
/// background task queue so inference never blocks the platform thread.
final class FaceEmbedderPlugin: NSObject, FlutterPlugin {
  private static let side = 112

  private let lock = NSLock()
  private var model: MLModel?
  private var input: MLMultiArray?

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(
      name: "poi/face_embedder",
      binaryMessenger: messenger,
      codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?())
    registrar.addMethodCallDelegate(FaceEmbedderPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    lock.lock()
    defer { lock.unlock() }
    do {
      switch call.method {
      case "load":
        try loadModel()
        result(nil)
      case "embed":
        guard let bytes = (call.arguments as? FlutterStandardTypedData)?.data,
          bytes.count == Self.side * Self.side * 3
        else {
          result(FlutterError(code: "bad_input", message: "expected 112x112 RGB bytes", details: nil))
          return
        }
        result(FlutterStandardTypedData(float32: try embed(bytes)))
      case "launchEnvironment":
        // Test hooks (POI_*). Dart's Platform.environment does not see
        // launch-time variables on iOS.
        result(ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("POI_") })
      case "log":
        // Diagnostics from Dart; NSLog reaches `devicectl ... --console`.
        NSLog("%@", (call.arguments as? String) ?? "")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "embedder", message: error.localizedDescription, details: nil))
    }
  }

  private func loadModel() throws {
    if model != nil { return }
    guard let url = Bundle.main.url(forResource: "FaceEmbedder", withExtension: "mlmodelc") else {
      throw NSError(
        domain: "FaceEmbedder", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "FaceEmbedder.mlmodelc is missing from the app bundle"])
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    model = try MLModel(contentsOf: url, configuration: config)
    input = try MLMultiArray(
      shape: [1, 3, NSNumber(value: Self.side), NSNumber(value: Self.side)], dataType: .float32)
  }

  private func embed(_ rgb: Data) throws -> Data {
    try loadModel()
    guard let model = model, let input = input else {
      throw NSError(domain: "FaceEmbedder", code: 2, userInfo: nil)
    }

    // Interleaved HWC bytes -> planar CHW floats in 0...255 (the model normalises).
    let plane = Self.side * Self.side
    let dst = input.dataPointer.bindMemory(to: Float32.self, capacity: plane * 3)
    rgb.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      let src = raw.bindMemory(to: UInt8.self)
      for i in 0..<plane {
        dst[i] = Float32(src[3 * i])
        dst[plane + i] = Float32(src[3 * i + 1])
        dst[2 * plane + i] = Float32(src[3 * i + 2])
      }
    }

    let features = try MLDictionaryFeatureProvider(dictionary: ["rgb": MLFeatureValue(multiArray: input)])
    guard let output = try model.prediction(from: features).featureValue(for: "embedding")?.multiArrayValue
    else {
      throw NSError(
        domain: "FaceEmbedder", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "model returned no embedding"])
    }

    var values = [Float32](repeating: 0, count: output.count)
    if output.dataType == .float32, output.strides.last?.intValue == 1 {
      let src = output.dataPointer.bindMemory(to: Float32.self, capacity: output.count)
      for i in 0..<output.count { values[i] = src[i] }
    } else {
      for i in 0..<output.count { values[i] = output[i].floatValue }
    }
    return values.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}
