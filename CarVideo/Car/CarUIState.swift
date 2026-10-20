import Foundation
import Observation

/// What the car screen is showing.
@Observable
@MainActor
final class CarUIState {
    static let shared = CarUIState()

    enum Screen: String {
        case home, player, youtube
    }

    var screen: Screen = .home
    var page = 0
    var controlsVisible = true
    var toolbarExpanded = true
    var keyboardVisible = false
    var keyboardText = ""
    /// Where the YouTube button is, in car-window points. The simulator test taps it to check touch input.
    var youTubeButtonFrame: CGRect = .zero
    /// Demo only: lay the car screen out at this size and shrink it to fit, to check bigger cars' layouts.
    var previewSize: CGSize?

    @ObservationIgnored private var hideControlsTask: Task<Void, Never>?
    @ObservationIgnored private var collapseToolbarTask: Task<Void, Never>?

    private init() {}

    func carConnected() {
        keyboardVisible = false
        let playback = PlaybackController.shared
        if playback.current != nil {
            // Something was playing on the iPhone: carry on here.
            playback.moveToCar()
            screen = .player
            showControls()
        } else if screen == .player {
            screen = .home
        }
    }

    func carDisconnected() {
        keyboardVisible = false
        hideControlsTask?.cancel()
        collapseToolbarTask?.cancel()
    }

    // MARK: - Videos

    func play(_ item: VideoItem, list: [VideoItem]) {
        if screen == .youtube { WebModel.car.pauseVideos() }
        PlaybackController.shared.play(item, in: list, on: .car)
        screen = .player
        showControls()
    }

    func closePlayer() {
        PlaybackController.shared.stop()
        screen = .home
    }

    func showControls() {
        controlsVisible = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if PlaybackController.shared.isPlaying {
                self.controlsVisible = false
            }
        }
    }

    func toggleControls() {
        if controlsVisible {
            hideControlsTask?.cancel()
            controlsVisible = false
        } else {
            showControls()
        }
    }

    // MARK: - YouTube

    /// Opens YouTube on the car screen, at `url` if given.
    func openYouTube(url: URL? = nil) {
        let playback = PlaybackController.shared
        if playback.output == .car, playback.isPlaying { playback.pause() }
        WebModel.car.ensureWebView(loading: url)
        screen = .youtube
        expandToolbar()
        Diagnostics.log("Car", "YouTube opened\(url.map { " at \($0.absoluteString)" } ?? "")")
    }

    func closeYouTube() {
        WebModel.car.pauseVideos()
        keyboardVisible = false
        screen = .home
    }

    func expandToolbar() {
        toolbarExpanded = true
        collapseToolbarTask?.cancel()
        collapseToolbarTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self.toolbarExpanded = false
        }
    }

    func collapseToolbar() {
        collapseToolbarTask?.cancel()
        toolbarExpanded = false
    }

    func showKeyboard() {
        guard screen == .youtube else { return }
        collapseToolbarTask?.cancel()
        keyboardVisible = true
    }

    func searchFromKeyboard() {
        let query = keyboardText
        keyboardVisible = false
        WebModel.car.search(query)
        Diagnostics.log("Car", "YouTube search \"\(query)\"")
    }
}
