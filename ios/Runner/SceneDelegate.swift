import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // Protect the window before the first frame is shown.
    if let window { ScreenSecurity.shared.protect(window: window) }
  }

  // Blank the app in the App Switcher snapshot.
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let window, privacyCover == nil else { return }
    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    cover.frame = window.bounds
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
