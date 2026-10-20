import AVFoundation
import CryptoKit
import UIKit

/// Video thumbnails: a frame about a tenth of the way in, cached in memory and as JPEGs on disk.
@MainActor
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 300
    }

    nonisolated private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Thumbnails", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    nonisolated private static func fileURL(for id: String) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".jpg")
    }

    func cached(_ item: VideoItem) -> UIImage? {
        cache.object(forKey: item.id as NSString)
    }

    func thumbnail(for item: VideoItem) async -> UIImage? {
        let key = item.id
        if let image = cache.object(forKey: key as NSString) { return image }
        if let running = inFlight[key] { return await running.value }
        let file = Self.fileURL(for: key)
        let source = item.url
        let duration = item.duration
        let task = Task.detached(priority: .utility) { await Self.loadOrMake(file: file, source: source, duration: duration) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }

    nonisolated private static func loadOrMake(file: URL, source: URL, duration: Double?) async -> UIImage? {
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let seconds = duration.map { $0 > 0 ? min(max($0 * 0.1, 1), 60) : 1 } ?? 2
        do {
            let (cgImage, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            let image = UIImage(cgImage: cgImage)
            if let jpeg = image.jpegData(compressionQuality: 0.8) {
                try? jpeg.write(to: file, options: .atomic)
            }
            return image
        } catch {
            return nil
        }
    }

    func remove(_ item: VideoItem) {
        cache.removeObject(forKey: item.id as NSString)
        try? FileManager.default.removeItem(at: Self.fileURL(for: item.id))
    }

    func clearAll() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.directory)
    }
}
