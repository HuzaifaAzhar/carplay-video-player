import Foundation

/// Files opened with the app ("Open in Car Video", share sheet) and `carvideo://` links:
/// - `carvideo://youtube?url=<YouTube link>` or `carvideo://youtube/<video id>` opens YouTube on the car screen
/// - `carvideo://play?url=<video link>` plays a direct link (on the car screen when connected)
@MainActor
enum IncomingURLs {
    static func handle(_ url: URL) {
        if url.isFileURL {
            Diagnostics.log("App", "Opened file \(url.lastPathComponent)")
            VideoLibrary.shared.importFiles([url])
            return
        }
        guard url.scheme?.lowercased() == "carvideo" else { return }
        Diagnostics.log("App", "Opened link \(url.absoluteString)")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let parameter = components?.queryItems?.first { $0.name == "url" }?.value
        let site = AppSettings.shared.youTubeSite
        switch url.host?.lowercased() {
        case "youtube":
            let pathID = url.pathComponents.dropFirst().first
            let target = parameter.flatMap { YouTube.pageURL(for: $0, site: site) }
                ?? pathID.flatMap { YouTube.watchURL(id: $0, site: site) }
            CarUIState.shared.openYouTube(url: target)
        case "play":
            guard let parameter, let link = URL(string: parameter) else { return }
            if let page = YouTube.pageURL(for: parameter, site: site) {
                CarUIState.shared.openYouTube(url: page)
                return
            }
            let item = VideoItem(id: "link:" + link.absoluteString, source: .stream(link),
                                 title: link.deletingPathExtension().lastPathComponent, folder: nil, dateAdded: Date(),
                                 fileSize: nil, duration: nil, width: nil, height: nil, position: 0, lastPlayed: nil, watched: false)
            if CarConnection.shared.isConnected {
                CarUIState.shared.play(item, list: [item])
            } else {
                PlaybackController.shared.play(item, in: [item], on: .phone)
            }
        default:
            break
        }
    }
}
