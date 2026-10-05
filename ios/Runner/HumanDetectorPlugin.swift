import CoreVideo
import Flutter
import Vision

/// Finds people in camera frames with Vision, including people facing away
/// or too far off for a face, so the Machine can mark them too.
///
/// `detect` takes an upright BGRA frame and returns a flat Float64List of
/// `x, y, width, height, confidence` per person, in frame pixels with the
/// origin top left. Runs on a background task queue.
final class HumanDetectorPlugin: NSObject, FlutterPlugin {
  private let request = VNDetectHumanRectanglesRequest()

  static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(
      name: "poi/humans",
      binaryMessenger: messenger,
      codec: FlutterStandardMethodCodec.sharedInstance(),
      taskQueue: messenger.makeBackgroundTaskQueue?())
    registrar.addMethodCallDelegate(HumanDetectorPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "detect" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
      let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let bytesPerRow = args["bytesPerRow"] as? Int,
      bytes.count >= bytesPerRow * height
    else {
      result(FlutterError(code: "bad_input", message: "expected a BGRA frame", details: nil))
      return
    }
    do {
      result(FlutterStandardTypedData(float64: try detect(bytes, width: width, height: height, bytesPerRow: bytesPerRow)))
    } catch {
      result(FlutterError(code: "vision", message: error.localizedDescription, details: nil))
    }
  }

  private func detect(_ bytes: Data, width: Int, height: Int, bytesPerRow: Int) throws -> Data {
    var boxes: [Double] = []
    try bytes.withUnsafeBytes { raw in
      // Wraps the frame without another copy; Vision is done with it before
      // this closure returns.
      var buffer: CVPixelBuffer?
      let status = CVPixelBufferCreateWithBytes(
        nil, width, height, kCVPixelFormatType_32BGRA,
        UnsafeMutableRawPointer(mutating: raw.baseAddress!), bytesPerRow,
        nil, nil, nil, &buffer)
      guard status == kCVReturnSuccess, let buffer else { throw DetectorError.buffer(status) }
      try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
    }
    let w = Double(width), h = Double(height)
    for person in request.results ?? [] {
      let box = person.boundingBox
      boxes += [box.minX * w, (1 - box.maxY) * h, box.width * w, box.height * h, Double(person.confidence)]
    }
    return boxes.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  enum DetectorError: LocalizedError {
    case buffer(CVReturn)

    var errorDescription: String? {
      switch self {
      case .buffer(let status): return "Could not wrap the frame (\(status))"
      }
    }
  }
}
