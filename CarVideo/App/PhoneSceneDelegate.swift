import SwiftUI
import UIKit

/// The iPhone window: hosts the SwiftUI interface and takes files and links opened with the app.
@MainActor
final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Diagnostics.log("Scene", "Phone window connected")
        AppBootstrap.start()
        PhoneScreen.shared.windowScene = windowScene
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: PhoneRootView())
        self.window = window
        window.makeKeyAndVisible()
        handle(connectionOptions.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(URLContexts)
    }

    private func handle(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            IncomingURLs.handle(context.url)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        VideoLibrary.shared.reload()
        CarConnection.shared.applyPhoneSettings()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        CarConnection.shared.restoreBrightness()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        PlaybackController.shared.saveProgress()
    }
}

/// The phone's own window scene, for its screen (brightness) and state.
@MainActor
final class PhoneScreen {
    static let shared = PhoneScreen()
    weak var windowScene: UIWindowScene?

    var isActive: Bool { windowScene?.activationState == .foregroundActive }
}
