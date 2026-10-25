import Flutter
import UIKit

/// iOS anti-capture layer.
///
/// iOS has no FLAG_SECURE. Content rendered inside the layer of a
/// `UITextField` with `isSecureTextEntry` is excluded by the system from
/// screenshots, screen recordings and AirPlay/mirroring, so the whole
/// window is re-parented into that layer. Recording/mirroring state and
/// screenshot events are also forwarded to Dart.
final class ScreenSecurity: NSObject, FlutterStreamHandler {
  static let shared = ScreenSecurity()

  private var sink: FlutterEventSink?
  private var secureField: UITextField?

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "overcome/security", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "enable":
          self?.protectKeyWindow()
          result(nil)
        case "isCaptured":
          result(ScreenSecurity.isCaptured)
        case "purgeRendererCache":
          result(nil)  // iOS renders PDFs from memory; nothing staged on disk.
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "overcome/security/events", binaryMessenger: messenger)
      .setStreamHandler(self)

    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(capturedChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)
  }

  static var isCaptured: Bool {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.screen.isCaptured }
      .contains(true)
  }

  /// Moves the window's layer under a secure text field's canvas layer.
  func protect(window: UIWindow) {
    guard secureField == nil else { return }
    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(field)
    NSLayoutConstraint.activate([
      field.centerXAnchor.constraint(equalTo: window.centerXAnchor),
      field.centerYAnchor.constraint(equalTo: window.centerYAnchor),
    ])
    window.layer.superlayer?.addSublayer(field.layer)
    // The secure canvas is the first sublayer on iOS 15–16 and the last
    // on iOS 17+.
    let canvas = (field.layer.sublayers?.last ?? field.layer.sublayers?.first)
    canvas?.addSublayer(window.layer)
    secureField = field
  }

  private func protectKeyWindow() {
    let window = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first
    if let window { protect(window: window) }
  }

  @objc private func capturedChanged() {
    sink?(["type": "captured", "value": ScreenSecurity.isCaptured])
  }

  @objc private func screenshotTaken() {
    sink?(["type": "screenshot"])
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
