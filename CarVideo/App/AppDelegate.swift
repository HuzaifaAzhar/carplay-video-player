import UIKit

/// UIKit app life cycle with two scene delegates: the iPhone window and the car screen.
/// (The SwiftUI `App` life cycle can claim the car scene itself and leave it black.)
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Diagnostics.installExceptionHandler()
        Diagnostics.log("App", "Launched \(Bundle.main.shortVersion) on iOS \(UIDevice.current.systemVersion)")
        AppBootstrap.start()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        Diagnostics.log("Scene", "Configuring scene for role \(role.rawValue)")
        if role == .carPlayWindow {
            let configuration = UISceneConfiguration(name: "CarPlay", sessionRole: role)
            configuration.delegateClass = CarSceneDelegate.self
            return configuration
        }
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: role)
        configuration.delegateClass = PhoneSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        Diagnostics.log("Scene", "Discarded \(sceneSessions.count) scene session(s)")
    }
}

extension UISceneSession.Role {
    /// The car screen as a plain window scene. UIKit doesn't expose this role in Swift, so it's built
    /// from the same raw string the Info.plist scene manifest uses.
    static let carPlayWindow = UISceneSession.Role(rawValue: "UIWindowSceneSessionRoleCarPlay")
}

@MainActor
enum AppBootstrap {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        PlaybackController.shared.configure()
        VideoLibrary.shared.reload()
    }
}

extension Bundle {
    var shortVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
