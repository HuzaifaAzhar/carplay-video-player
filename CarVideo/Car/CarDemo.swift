import Foundation

/// Automated walk-through of every car screen for the CarPlay simulator test (launch argument
/// `-CarVideoDemo YES`). It logs "[Demo] shot <name>" when a screen is ready to photograph and
/// "[Demo] tap <x> <y>" (car points) when it wants a real tap, which the test performs to prove touch works.
@MainActor
enum CarDemo {
    private static var task: Task<Void, Never>?

    static func start() {
        task?.cancel()
        task = Task { await run() }
    }

    static func stop() {
        task?.cancel()
        task = nil
    }

    private static func log(_ message: String) {
        Diagnostics.log("Demo", message)
    }

    private static func wait(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private static func run() async {
        let ui = CarUIState.shared
        guard await wait(4), let info = CarConnection.shared.info else { return }
        log("start screen \(info.pointSize.text) pt scale \(info.scale) native \(info.nativeSize.text) usable \(info.usableText) insets \(info.insetsText)")
        ui.screen = .home
        ui.page = 0
        guard await wait(2) else { return }
        log("shot home")
        guard await wait(2) else { return }

        // A real tap on the YouTube button, sent by the test through the Simulator window.
        let frame = ui.youTubeButtonFrame
        if frame.width > 0 {
            log("tap \(Int(frame.midX)) \(Int(frame.midY))")
            for _ in 0..<30 where ui.screen != .youtube {
                guard await wait(0.5) else { return }
            }
            log(ui.screen == .youtube ? "touch ok" : "touch not received")
        }
        if ui.screen != .youtube { ui.openYouTube() }
        let loads = WebModel.car.finishedLoads
        for _ in 0..<40 where WebModel.car.finishedLoads == loads {
            guard await wait(0.5) else { return }
        }
        guard await wait(6) else { return }
        log("shot youtube-home")

        ui.keyboardText = "lofi hip hop"
        ui.showKeyboard()
        guard await wait(1.5) else { return }
        log("shot keyboard")
        ui.searchFromKeyboard()
        guard await wait(10) else { return }
        log("shot youtube-search")
        ui.collapseToolbar()
        guard await wait(1.5) else { return }
        log("shot youtube-collapsed")
        ui.closeYouTube()

        let videos = VideoLibrary.shared.carList(.name)
        for video in videos.prefix(4) {
            ui.play(video, list: videos)
            guard await wait(3) else { return }
            log("shot player-\(slug(video.title))-controls")
            ui.controlsVisible = false
            guard await wait(1.5) else { return }
            log("shot player-\(slug(video.title))")
        }
        ui.closePlayer()
        guard await wait(1.5) else { return }
        log("shot home-end")
        log("done")
    }

    private static func slug(_ text: String) -> String {
        let allowed = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}
