import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // A surveillance feed should not go dark while someone is watching it.
    application.isIdleTimerDisabled = true
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "FaceEmbedderPlugin") {
      FaceEmbedderPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "MachineNativePlugin") {
      MachineNativePlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "HumanDetectorPlugin") {
      HumanDetectorPlugin.register(with: registrar)
    }
  }
}
