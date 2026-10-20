import Observation
import UIKit

/// What the car screen reports about itself, logged and shown in Settings so layout problems in a
/// particular car can be diagnosed.
struct CarScreenInfo: Equatable {
    var pointSize: CGSize
    var scale: CGFloat
    var nativeSize: CGSize
    /// The area the app's window gets, and the part covered by the CarPlay dock/status bar.
    var layoutSize: CGSize
    var safeArea: UIEdgeInsets

    var pixelText: String { "\(nativeSize.text) px" }
    var usableText: String {
        let w = layoutSize.width - safeArea.left - safeArea.right
        let h = layoutSize.height - safeArea.top - safeArea.bottom
        return "\(CGSize(width: w, height: h).text) pt"
    }
    var insetsText: String {
        let parts = [("top", safeArea.top), ("left", safeArea.left), ("bottom", safeArea.bottom), ("right", safeArea.right)]
            .filter { $0.1 > 0 }
            .map { "\($0.0) \(Int($0.1.rounded()))" }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ") + " pt"
    }
}

/// Tracks the car screen and applies the iPhone-side settings while it's connected.
@Observable
@MainActor
final class CarConnection {
    static let shared = CarConnection()

    private(set) var isConnected = false
    private(set) var info: CarScreenInfo?

    @ObservationIgnored private weak var windowScene: UIWindowScene?
    @ObservationIgnored private var savedBrightness: CGFloat?

    private init() {}

    func connected(windowScene: UIWindowScene) {
        self.windowScene = windowScene
        let screen = windowScene.screen
        info = CarScreenInfo(pointSize: screen.bounds.size, scale: screen.scale, nativeSize: screen.nativeBounds.size,
                             layoutSize: screen.bounds.size, safeArea: .zero)
        isConnected = true
        VideoLibrary.shared.reload()
        CarUIState.shared.carConnected()
        applyPhoneSettings()
        DrivingMonitor.shared.update()
        if AppSettings.shared.demoMode {
            CarDemo.start()
        }
    }

    func disconnected() {
        isConnected = false
        info = nil
        windowScene = nil
        CarDemo.stop()
        PlaybackController.shared.carDisconnected()
        CarUIState.shared.carDisconnected()
        WebModel.car.pauseVideos()
        UIApplication.shared.isIdleTimerDisabled = false
        restoreBrightness()
        DrivingMonitor.shared.update()
    }

    func updateLayout(size: CGSize, insets: UIEdgeInsets) {
        guard var current = info, current.layoutSize != size || current.safeArea != insets else { return }
        current.layoutSize = size
        current.safeArea = insets
        info = current
        Diagnostics.log("Car", "Car layout \(size.text) pt, safe area \(current.insetsText), usable \(current.usableText)")
    }

    /// Keeps the iPhone awake (and optionally dark) while it's driving the car screen. Both only work
    /// while this app is the one open on the iPhone.
    func applyPhoneSettings() {
        let settings = AppSettings.shared
        UIApplication.shared.isIdleTimerDisabled = isConnected && settings.keepPhoneAwake
        if isConnected, settings.dimPhone, PhoneScreen.shared.isActive, let screen = PhoneScreen.shared.windowScene?.screen {
            if savedBrightness == nil { savedBrightness = screen.brightness }
            screen.brightness = 0.02
        } else {
            restoreBrightness()
        }
    }

    func restoreBrightness() {
        guard let saved = savedBrightness else { return }
        savedBrightness = nil
        PhoneScreen.shared.windowScene?.screen.brightness = saved
    }
}
