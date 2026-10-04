import Flutter
import UIKit
import WidgetKit

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NeedTODOWidget") else { return }
    let channel = FlutterMethodChannel(name: "com.needtodo/platform", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "widgetUpdate":
        guard let snapshot = call.arguments as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.needtodo.shared") else {
          result(FlutterError(code: "app-group", message: "小组件共享空间不可用", details: nil)); return
        }
        do {
          try Data(snapshot.utf8).write(to: container.appendingPathComponent("snapshot.json"), options: .atomic)
          WidgetCenter.shared.reloadTimelines(ofKind: "NeedTODOCalendar")
          result(nil)
        } catch { result(FlutterError(code: "widget-write", message: "小组件更新失败", details: nil)) }
      case "widgetPin": result(false)
      case "widgetLaunch": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
