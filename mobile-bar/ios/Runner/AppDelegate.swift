import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The bar's and kitchen's tablets and the ready board keep the screen on while
    // they're open (brewdiary/awake); everywhere else the phone sleeps as usual.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BrewdiaryAwake") {
      FlutterMethodChannel(name: "brewdiary/awake", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
        if call.method == "set" {
          UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
