import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  FlutterStreamHandler
{
  private var accessibilityEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let methodChannel = FlutterMethodChannel(
      name: "xyz.iawnix.ts_phone/accessibility",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { call, result in
      guard call.method == "getReduceTransparencyEnabled" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(UIAccessibility.isReduceTransparencyEnabled)
    }

    let eventChannel = FlutterEventChannel(
      name: "xyz.iawnix.ts_phone/accessibility_changes",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    accessibilityEventSink = events
    events(UIAccessibility.isReduceTransparencyEnabled)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(reduceTransparencyDidChange),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(
      self,
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
    accessibilityEventSink = nil
    return nil
  }

  @objc private func reduceTransparencyDidChange() {
    accessibilityEventSink?(UIAccessibility.isReduceTransparencyEnabled)
  }
}
