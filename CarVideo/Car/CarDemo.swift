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

    /// Asks the test for a screenshot and gives it time to take one before the screen changes.
    private static func shot(_ name: String) async -> Bool {
        log("shot \(name)")
        return await wait(2.5)
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
        guard await shot("home") else { return }
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
        guard await shot("youtube-home") else { return }

        ui.keyboardText = "lofi hip hop"
        ui.showKeyboard()
        guard await wait(1.5) else { return }
        guard await shot("keyboard") else { return }
        ui.searchFromKeyboard()
        guard await wait(10) else { return }
        guard await shot("youtube-search") else { return }
        ui.collapseToolbar()
        guard await wait(1.5) else { return }
        guard await shot("youtube-collapsed") else { return }
        ui.closeYouTube()

        let videos = VideoLibrary.shared.carList(.name)
        for video in videos.prefix(4) {
            ui.play(video, list: videos)
            guard await wait(3) else { return }
            guard await shot("player-\(slug(video.title))-controls") else { return }
            ui.controlsVisible = false
            guard await wait(1.5) else { return }
            guard await shot("player-\(slug(video.title))") else { return }
        }
        ui.closePlayer()
        guard await wait(1.5) else { return }
        guard await shot("home-end") else { return }

        // Other real car sizes (usable area in points), laid out at that size and shrunk to fit.
        let sizes = [CGSize(width: 420, height: 263),   // 1280×720 panel at @2.74
                     CGSize(width: 590, height: 360),   // 1280×720 at @2
                     CGSize(width: 900, height: 360),   // 1920×720 ultra-wide at @2
                     CGSize(width: 640, height: 560)]   // tall unit
        for size in sizes {
            let name = "preview-\(Int(size.width))x\(Int(size.height))"
            ui.previewSize = size
            ui.screen = .home
            guard await wait(1.5), await shot("\(name)-home") else { break }
            if let video = videos.first {
                ui.play(video, list: videos)
                guard await wait(2), await shot("\(name)-player") else { break }
            }
            ui.openYouTube()
            guard await wait(4), await shot("\(name)-youtube") else { break }
            ui.keyboardText = "news"
            ui.showKeyboard()
            guard await wait(1), await shot("\(name)-keyboard") else { break }
            ui.keyboardVisible = false
            ui.closeYouTube()
        }
        ui.previewSize = nil
        ui.closePlayer()
        log("done")
    }

    private static func slug(_ text: String) -> String {
        let allowed = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}
