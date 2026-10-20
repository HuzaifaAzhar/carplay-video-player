import AVFoundation
import Foundation
import Observation

/// A video on the iPhone (a file in the app's Documents folder) or a saved link that streams.
struct VideoItem: Identifiable, Hashable {
    enum Source: Hashable {
        case file(relativePath: String)
        case stream(URL)
    }

    let id: String
    var source: Source
    var title: String
    /// Subfolder inside the app's Files folder, if any.
    var folder: String?
    var dateAdded: Date
    var fileSize: Int64?
    var duration: Double?
    var width: Int?
    var height: Int?
    var position: Double
    var lastPlayed: Date?
    var watched: Bool

    var url: URL {
        switch source {
        case .file(let path): return VideoLibrary.documents.appendingPathComponent(path)
        case .stream(let url): return url
        }
    }

    var isStream: Bool {
        if case .stream = source { return true }
        return false
    }

    /// Fraction watched, when there's a saved position.
    var progress: Double? {
        guard let duration, duration > 0, position > 0 else { return nil }
        return min(1, position / duration)
    }

    var isInProgress: Bool {
        guard !watched, let progress else { return false }
        return progress > 0.01 && progress < 0.97
    }

    var resolutionText: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }
}

private struct StoredVideoState: Codable {
    var position: Double = 0
    var lastPlayed: Date?
    var watched = false
    var duration: Double?
    var width: Int?
    var height: Int?
}

private struct StoredStream: Codable {
    var id: UUID
    var title: String
    var url: URL
    var dateAdded: Date
}

private struct StoredLibrary: Codable {
    var states: [String: StoredVideoState] = [:]
    var streams: [StoredStream] = []
}

/// Every video the app can play: files in its Documents folder (visible in the Files app, so videos can be
/// dropped in from anywhere) plus saved links. Positions and watched state persist per video.
@Observable
@MainActor
final class VideoLibrary {
    static let shared = VideoLibrary()

    /// Formats iOS's own player can open.
    nonisolated static let playableExtensions: Set<String> = ["mp4", "m4v", "mov", "3gp", "3g2"]
    /// Common video formats it can't, listed so the app can say why a file doesn't show up.
    nonisolated static let unsupportedExtensions: Set<String> = ["mkv", "webm", "avi", "wmv", "flv", "mpg", "mpeg", "ts", "vob", "ogv", "rmvb"]

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("library.json")
    }

    private(set) var videos: [VideoItem] = []
    private(set) var folders: [String] = []
    /// Files that are videos but in formats iOS can't play.
    private(set) var unsupportedFiles: [String] = []
    private(set) var isImporting = false
    var lastImportMessage: String?

    @ObservationIgnored private var store = StoredLibrary()
    @ObservationIgnored private var metadataTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private init() {
        if let data = try? Data(contentsOf: Self.storeURL),
           let decoded = try? JSONDecoder().decode(StoredLibrary.self, from: data) {
            store = decoded
        }
    }

    // MARK: - Scanning

    func reload() {
        let fm = FileManager.default
        let root = Self.documents.resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .addedToDirectoryDateKey]
        var items: [VideoItem] = []
        var unsupported: [String] = []

        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let url as URL in enumerator {
                let path = url.resolvingSymlinksInPath().path
                guard path.hasPrefix(rootPath) else { continue }
                let relative = String(path.dropFirst(rootPath.count))
                if relative == "Inbox" || relative.hasPrefix("Inbox/") { continue }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let ext = url.pathExtension.lowercased()
                if Self.unsupportedExtensions.contains(ext) {
                    unsupported.append(relative)
                    continue
                }
                guard Self.playableExtensions.contains(ext) else { continue }
                let id = "file:" + relative
                let state = store.states[id] ?? StoredVideoState()
                let folder = relative.contains("/") ? (relative as NSString).deletingLastPathComponent : nil
                items.append(VideoItem(
                    id: id, source: .file(relativePath: relative),
                    title: url.deletingPathExtension().lastPathComponent, folder: folder,
                    dateAdded: values.addedToDirectoryDate ?? values.creationDate ?? .distantPast,
                    fileSize: values.fileSize.map { Int64($0) },
                    duration: state.duration, width: state.width, height: state.height,
                    position: state.position, lastPlayed: state.lastPlayed, watched: state.watched))
            }
        }

        for stream in store.streams {
            let id = "stream:" + stream.id.uuidString
            let state = store.states[id] ?? StoredVideoState()
            items.append(VideoItem(
                id: id, source: .stream(stream.url), title: stream.title, folder: nil,
                dateAdded: stream.dateAdded, fileSize: nil,
                duration: state.duration, width: state.width, height: state.height,
                position: state.position, lastPlayed: state.lastPlayed, watched: state.watched))
        }

        if items != videos { videos = items }
        let newFolders = Array(Set(items.compactMap(\.folder))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if newFolders != folders { folders = newFolders }
        let newUnsupported = unsupported.sorted()
        if newUnsupported != unsupportedFiles { unsupportedFiles = newUnsupported }
        loadMissingMetadata()
    }

    func item(id: String) -> VideoItem? {
        videos.first { $0.id == id }
    }

    /// Duration and picture size for files that haven't been looked at yet, one at a time.
    private func loadMissingMetadata() {
        guard metadataTask == nil else { return }
        let pending = videos.filter { $0.duration == nil && !$0.isStream }.map { ($0.id, $0.url) }
        guard !pending.isEmpty else { return }
        metadataTask = Task {
            for (id, url) in pending {
                let info = await VideoMetadata.load(url)
                self.applyMetadata(id: id, info)
            }
            self.metadataTask = nil
            self.loadMissingMetadata()
        }
    }

    private func applyMetadata(id: String, _ info: VideoMetadata.Info) {
        var state = store.states[id] ?? StoredVideoState()
        // Unreadable files get a zero duration so they aren't retried on every scan.
        state.duration = info.duration ?? 0
        state.width = info.width
        state.height = info.height
        store.states[id] = state
        if let index = videos.firstIndex(where: { $0.id == id }) {
            videos[index].duration = state.duration
            videos[index].width = info.width
            videos[index].height = info.height
        }
        scheduleSave()
    }

    // MARK: - Sorting and filtering

    func sorted(_ items: [VideoItem], by sort: LibrarySort) -> [VideoItem] {
        items.sorted { a, b in
            switch sort {
            case .dateAddedNewest: return a.dateAdded > b.dateAdded
            case .dateAddedOldest: return a.dateAdded < b.dateAdded
            case .nameAZ: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .nameZA: return a.title.localizedStandardCompare(b.title) == .orderedDescending
            case .lastPlayed: return (a.lastPlayed ?? .distantPast, a.dateAdded) > (b.lastPlayed ?? .distantPast, b.dateAdded)
            case .durationLongest: return (a.duration ?? 0) > (b.duration ?? 0)
            case .durationShortest: return (a.duration ?? .infinity) < (b.duration ?? .infinity)
            case .sizeLargest: return (a.fileSize ?? 0) > (b.fileSize ?? 0)
            case .sizeSmallest: return (a.fileSize ?? .max) < (b.fileSize ?? .max)
            }
        }
    }

    func filtered(search: String, sort: LibrarySort, filter: LibraryFilter, folder: String?) -> [VideoItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = videos.filter { item in
            if let folder, item.folder != folder, !(item.folder ?? "").hasPrefix(folder + "/") { return false }
            switch filter {
            case .all: break
            case .unwatched: if item.watched || item.isInProgress { return false }
            case .inProgress: if !item.isInProgress { return false }
            case .watched: if !item.watched { return false }
            case .files: if item.isStream { return false }
            case .streams: if !item.isStream { return false }
            }
            return query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
        }
        return sorted(items, by: sort)
    }

    /// The car screen's list.
    func carList(_ sort: CarSort) -> [VideoItem] {
        switch sort {
        case .recentlyAdded: return sorted(videos, by: .dateAddedNewest)
        case .recentlyPlayed: return sorted(videos, by: .lastPlayed)
        case .name: return sorted(videos, by: .nameAZ)
        }
    }

    // MARK: - Progress

    func updatePosition(id: String, position: Double, duration: Double?) {
        var state = store.states[id] ?? StoredVideoState()
        state.position = max(0, position)
        if let duration, duration > 0 { state.duration = duration }
        let nearEnd = (state.duration ?? 0) > 0 && position >= (state.duration ?? 0) - 15
        if nearEnd { state.watched = true }
        store.states[id] = state
        if let index = videos.firstIndex(where: { $0.id == id }) {
            videos[index].position = state.position
            videos[index].duration = state.duration
            videos[index].watched = state.watched
        }
        scheduleSave()
    }

    func markPlayed(id: String) {
        var state = store.states[id] ?? StoredVideoState()
        state.lastPlayed = Date()
        store.states[id] = state
        if let index = videos.firstIndex(where: { $0.id == id }) {
            videos[index].lastPlayed = state.lastPlayed
        }
        scheduleSave()
    }

    func setWatched(id: String, _ watched: Bool) {
        var state = store.states[id] ?? StoredVideoState()
        state.watched = watched
        state.position = 0
        store.states[id] = state
        if let index = videos.firstIndex(where: { $0.id == id }) {
            videos[index].watched = watched
            videos[index].position = 0
        }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    // MARK: - Adding and removing

    /// Copies videos picked in the Files app (or opened with the app) into its folder.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Self.copyIn(urls) }.value
            self.isImporting = false
            self.lastImportMessage = result.message
            self.reload()
        }
    }

    /// Files are copied, not moved, except ones iOS already handed us in the Inbox folder.
    nonisolated private static func copyIn(_ urls: [URL]) -> (count: Int, message: String) {
        let fm = FileManager.default
        var copied = 0
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let destination = uniqueDestination(for: url.lastPathComponent)
            do {
                if url.path.contains("/Documents/Inbox/") {
                    try fm.moveItem(at: url, to: destination)
                } else {
                    try fm.copyItem(at: url, to: destination)
                }
                copied += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        var message = copied == 1 ? "Added 1 video." : "Added \(copied) videos."
        if !failures.isEmpty { message += " Couldn't add " + failures.joined(separator: "; ") }
        return (copied, message)
    }

    /// A free file name in the app's folder, adding " 2", " 3"… when the name is taken.
    nonisolated static func uniqueDestination(for fileName: String) -> URL {
        let fm = FileManager.default
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = documents.appendingPathComponent(fileName)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = documents.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }

    func addStream(title: String, url: URL) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? (url.deletingPathExtension().lastPathComponent.isEmpty ? url.host ?? "Video" : url.deletingPathExtension().lastPathComponent) : trimmed
        store.streams.append(StoredStream(id: UUID(), title: name, url: url, dateAdded: Date()))
        saveNow()
        reload()
    }

    func delete(_ item: VideoItem) {
        switch item.source {
        case .file:
            do {
                try FileManager.default.removeItem(at: item.url)
            } catch {
                lastImportMessage = "Couldn't delete \(item.title): \(error.localizedDescription)"
            }
        case .stream:
            store.streams.removeAll { "stream:" + $0.id.uuidString == item.id }
        }
        store.states[item.id] = nil
        ThumbnailStore.shared.remove(item)
        saveNow()
        reload()
    }

    var totalFileSize: Int64 {
        videos.reduce(0) { $0 + ($1.fileSize ?? 0) }
    }
}

/// Reads a video's duration and picture size.
enum VideoMetadata {
    struct Info: Sendable {
        var duration: Double?
        var width: Int?
        var height: Int?
    }

    static func load(_ url: URL) async -> Info {
        let asset = AVURLAsset(url: url)
        var info = Info()
        if let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 {
            info.duration = duration.seconds
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
            info.width = Int(abs(rect.width).rounded())
            info.height = Int(abs(rect.height).rounded())
        }
        return info
    }
}

extension Double {
    /// "1:02:03" or "4:05".
    var clockText: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension Int64 {
    var byteText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}
