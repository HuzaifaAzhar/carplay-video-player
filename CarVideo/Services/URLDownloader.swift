import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// Downloads a video from a direct link into the app's folder, with progress.
@Observable
@MainActor
final class URLDownloader {
    static let shared = URLDownloader()

    struct Job: Identifiable {
        let id: Int
        let url: URL
        var name: String
        var received: Int64 = 0
        var expected: Int64 = 0
        var error: String?

        var fraction: Double? {
            expected > 0 ? Double(received) / Double(expected) : nil
        }
    }

    private(set) var jobs: [Job] = []

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var tasks: [Int: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        session = URLSession(configuration: .default, delegate: DownloadDelegate(), delegateQueue: nil)
    }

    func download(_ url: URL, name: String?) {
        let task = session.downloadTask(with: url)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        task.taskDescription = trimmed
        tasks[task.taskIdentifier] = task
        jobs.append(Job(id: task.taskIdentifier, url: url, name: trimmed.isEmpty ? url.lastPathComponent : trimmed))
        task.resume()
        keepRunningInBackground()
        Diagnostics.log("Download", "Started \(url.absoluteString)")
    }

    func cancel(_ id: Int) {
        tasks[id]?.cancel()
        tasks[id] = nil
        jobs.removeAll { $0.id == id }
        finishBackgroundTaskIfIdle()
    }

    func dismiss(_ id: Int) {
        jobs.removeAll { $0.id == id }
    }

    fileprivate func progress(id: Int, received: Int64, expected: Int64) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].received = received
        jobs[index].expected = expected
    }

    fileprivate func finished(id: Int, file: URL) {
        tasks[id] = nil
        jobs.removeAll { $0.id == id }
        Diagnostics.log("Download", "Saved \(file.lastPathComponent)")
        VideoLibrary.shared.lastImportMessage = "Downloaded \(file.deletingPathExtension().lastPathComponent)."
        VideoLibrary.shared.reload()
        finishBackgroundTaskIfIdle()
    }

    fileprivate func failed(id: Int, message: String) {
        tasks[id] = nil
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].error = message
        }
        Diagnostics.log("Download", "Failed: \(message)")
        finishBackgroundTaskIfIdle()
    }

    /// A few extra minutes to finish when the app is sent to the background.
    private func keepRunningInBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Video download") {
            MainActor.assumeIsolated { URLDownloader.shared.endBackgroundTask() }
        }
    }

    private func finishBackgroundTaskIfIdle() {
        if tasks.isEmpty { endBackgroundTask() }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

/// Runs on the session's own queue. The finished file must be moved before returning.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let http = downloadTask.response as? HTTPURLResponse
        if let status = http?.statusCode, !(200..<300).contains(status) {
            Task { @MainActor in URLDownloader.shared.failed(id: id, message: "The server answered HTTP \(status).") }
            return
        }
        let mime = downloadTask.response?.mimeType?.lowercased() ?? ""
        if mime.hasPrefix("text/") || mime.contains("html") || mime.contains("json") {
            Task { @MainActor in URLDownloader.shared.failed(id: id, message: "That link is a web page (\(mime)), not a video file.") }
            return
        }
        let fileName = Self.fileName(for: downloadTask)
        let destination = VideoLibrary.uniqueDestination(for: fileName)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in URLDownloader.shared.finished(id: id, file: destination) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in URLDownloader.shared.failed(id: id, message: message) }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        Task { @MainActor in URLDownloader.shared.progress(id: id, received: totalBytesWritten, expected: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        let id = task.taskIdentifier
        let message = error.localizedDescription
        Task { @MainActor in URLDownloader.shared.failed(id: id, message: message) }
    }

    /// The name the user gave, else the server's, with a video extension the player recognises.
    private static func fileName(for task: URLSessionDownloadTask) -> String {
        let given = task.taskDescription ?? ""
        let suggested = task.response?.suggestedFilename ?? task.originalRequest?.url?.lastPathComponent ?? "Video"
        var ext = (suggested as NSString).pathExtension.lowercased()
        if !VideoLibrary.playableExtensions.contains(ext) {
            if let mime = task.response?.mimeType, let type = UTType(mimeType: mime), let preferred = type.preferredFilenameExtension,
               VideoLibrary.playableExtensions.contains(preferred) {
                ext = preferred
            } else {
                ext = "mp4"
            }
        }
        let base = given.isEmpty ? (suggested as NSString).deletingPathExtension : given
        let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return (safe.isEmpty ? "Video" : safe) + "." + ext
    }
}
