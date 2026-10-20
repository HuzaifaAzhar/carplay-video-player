import SwiftUI
import UIKit

/// The car screen. A plain `UIWindowScene` on the CarPlay display (role `UIWindowSceneSessionRoleCarPlay`),
/// not a CarPlay template scene, so anything UIKit draws (video, a web view) appears on the head unit and
/// takes touches from it. iOS creates this scene for apps with the private `SBStarkCapable` entitlement
/// (TrollStore installs), and from iOS 26.4 for apps Apple grants the CarPlay video entitlement.
@MainActor
final class CarSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let screen = windowScene.screen
        Diagnostics.log("Car", "Car screen connected: \(screen.bounds.size.text) pt at @\(screen.scale)x, "
            + "native \(screen.nativeBounds.size.text) px, idiom \(windowScene.traitCollection.userInterfaceIdiom.rawValue), "
            + "\(screen.maximumFramesPerSecond) fps")
        AppBootstrap.start()
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = CarHostingController(rootView: CarRootView())
        self.window = window
        window.makeKeyAndVisible()
        CarConnection.shared.connected(windowScene: windowScene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Diagnostics.log("Car", "Car screen active")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Diagnostics.log("Car", "Car screen inactive")
        PlaybackController.shared.saveProgress()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Diagnostics.log("Car", "Car screen disconnected")
        window = nil
        CarConnection.shared.disconnected()
    }
}

/// Hosts the car interface and reports the area it's given: the CarPlay dock and status bar arrive as
/// safe-area insets, which the layout keeps clear of.
final class CarHostingController: UIHostingController<CarRootView> {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CarConnection.shared.updateLayout(size: view.bounds.size, insets: view.safeAreaInsets)
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

extension CGSize {
    var text: String { "\(Int(width.rounded()))×\(Int(height.rounded()))" }
}
