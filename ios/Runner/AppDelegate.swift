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
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "io.github.caolib.kira/app_icon",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setAppIcon":
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(code: "icon_unsupported", message: "当前设备不支持切换应用图标。", details: nil))
          return
        }
        guard let arguments = call.arguments as? [String: Any],
          let idx = arguments["index"] as? Int,
          (0...1).contains(idx)
        else {
          result(FlutterError(code: "invalid_icon", message: "应用图标编号无效。", details: nil))
          return
        }
        let iconName = idx == 0 ? nil : "AppIcon-1"
        guard UIApplication.shared.alternateIconName != iconName else {
          result(nil)
          return
        }
        UIApplication.shared.setAlternateIconName(iconName) { error in
          if let error = error {
            result(FlutterError(code: "icon_error", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      case "getAppIconIndex":
        let current = UIApplication.shared.alternateIconName
        result(current == nil ? 0 : 1)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
