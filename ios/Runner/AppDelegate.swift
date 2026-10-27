import Flutter
import GoogleCast
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ChameleonCastStyle") {
      CastStyle.register(with: registrar.messenger())
    }
  }
}

/// Styles the subtitles on the Chromecast being cast to, like the app's own (see
/// lib/core/cast/cast_controller.dart). The Cast plugin doesn't pass styles on, so this sets them
/// on the current session with Google's Cast SDK directly. "set" takes the same as on Android
/// (CastStyle.kt), and answers false when nothing is being cast.
enum CastStyle {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "chameleon/cast_style", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "set", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard GCKCastContext.isSharedInstanceInitialized(),
        let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
      else {
        result(false)
        return
      }
      client.setTextTrackStyle(style(args))
      result(true)
    }
  }

  private static func style(_ args: [String: Any]) -> GCKMediaTextTrackStyle {
    let style = GCKMediaTextTrackStyle.createDefault()
    switch args["edge"] as? String {
    case "outline": style.edgeType = .outline
    case "dropShadow": style.edgeType = .dropShadow
    default: style.edgeType = .none
    }
    if let argb = args["edgeColor"] as? Int { style.edgeColor = color(argb) }
    if let argb = args["foreground"] as? Int { style.foregroundColor = color(argb) }
    if let argb = args["background"] as? Int { style.backgroundColor = color(argb) }
    if let scale = args["scale"] as? Double { style.fontScale = CGFloat(scale) }
    switch args["font"] as? String {
    case "serif": style.fontGenericFamily = .serif
    case "monospacedSansSerif": style.fontGenericFamily = .monospacedSansSerif
    case "monospacedSerif": style.fontGenericFamily = .monospacedSerif
    case "casual": style.fontGenericFamily = .casual
    case "cursive": style.fontGenericFamily = .cursive
    case "smallCapitals": style.fontGenericFamily = .smallCapitals
    default: style.fontGenericFamily = .sansSerif
    }
    style.windowType = .none
    return style
  }

  private static func color(_ argb: Int) -> GCKColor {
    GCKColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}
