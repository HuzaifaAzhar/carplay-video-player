import Foundation
import os

/// Small persistent log for things that only happen in the car, viewable in Settings → Diagnostics and in
/// the device console under subsystem "com.huzaifa.carvideo". The automated CarPlay simulator test also
/// reads it to follow the demo run.
enum Diagnostics {
    private static let logger = Logger(subsystem: "com.huzaifa.carvideo", category: "Diagnostics")
    private static let queue = DispatchQueue(label: "CarVideo.diagnostics")
    private static let maxBytes = 200_000

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Diagnostics", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("diagnostics.log")
    }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func log(_ category: String, _ message: String) {
        logger.notice("[\(category, privacy: .public)] \(message, privacy: .public)")
        let line = "\(timestamp.string(from: Date())) [\(category)] \(message)\n"
        queue.async { append(line) }
    }

    /// Synchronous write, for crash handlers.
    static func logImmediately(_ category: String, _ message: String) {
        let line = "\(timestamp.string(from: Date())) [\(category)] \(message)\n"
        queue.sync { append(line) }
    }

    private static func append(_ line: String) {
        let url = fileURL
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            let start = (try? handle.seekToEnd()) ?? 0
            try? handle.write(contentsOf: data)
            try? handle.close()
            if start + UInt64(data.count) > UInt64(maxBytes), let all = try? Data(contentsOf: url) {
                // Keep the newest half.
                try? all.suffix(maxBytes / 2).write(to: url, options: .atomic)
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func read() -> String {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
    }

    static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Objective-C exceptions would otherwise vanish with the crash.
    static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "no reason"
            let stack = exception.callStackSymbols.prefix(12).joined(separator: "\n    ")
            Diagnostics.logImmediately("CRASH", "\(exception.name.rawValue): \(reason)\n    \(stack)")
        }
    }
}
