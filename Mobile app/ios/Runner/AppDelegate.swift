import Flutter
import CoreMotion
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
    let channel = FlutterMethodChannel(
      name: "roadguard/device_capabilities",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "deviceCapabilities" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let motion = CMMotionManager()
      result([
        "accelerometer": motion.isAccelerometerAvailable,
        "gyroscope": motion.isGyroAvailable,
        "camera": UIImagePickerController.isSourceTypeAvailable(.camera)
      ])
    }
  }
}
