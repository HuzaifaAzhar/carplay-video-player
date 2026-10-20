import Foundation
import Observation

enum VideoFit: String, CaseIterable, Identifiable {
    case fit, fill
    var id: String { rawValue }
    var title: String { self == .fit ? "Fit (whole picture)" : "Fill (crop edges)" }
}

enum YouTubeSite: String, CaseIterable, Identifiable {
    case mobile, desktop
    var id: String { rawValue }
    var title: String { self == .mobile ? "Mobile site" : "Desktop site" }
}

/// Sort order on the car screen, switched with one button there.
enum CarSort: String, CaseIterable {
    case recentlyAdded, recentlyPlayed, name

    var title: String {
        switch self {
        case .recentlyAdded: return "Newest"
        case .recentlyPlayed: return "Recent"
        case .name: return "A–Z"
        }
    }

    var symbol: String {
        switch self {
        case .recentlyAdded: return "calendar"
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .name: return "textformat"
        }
    }

    var next: CarSort {
        let all = CarSort.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case dateAddedNewest, dateAddedOldest, nameAZ, nameZA, lastPlayed, durationLongest, durationShortest, sizeLargest, sizeSmallest
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAddedNewest: return "Date Added (Newest)"
        case .dateAddedOldest: return "Date Added (Oldest)"
        case .nameAZ: return "Name (A–Z)"
        case .nameZA: return "Name (Z–A)"
        case .lastPlayed: return "Recently Played"
        case .durationLongest: return "Longest"
        case .durationShortest: return "Shortest"
        case .sizeLargest: return "Largest File"
        case .sizeSmallest: return "Smallest File"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, unwatched, inProgress, watched, files, streams
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Videos"
        case .unwatched: return "Unwatched"
        case .inProgress: return "In Progress"
        case .watched: return "Watched"
        case .files: return "On This iPhone"
        case .streams: return "Links (Streaming)"
        }
    }
}

/// User settings, stored in UserDefaults.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()
    @ObservationIgnored private let defaults = UserDefaults.standard

    // Car screen
    var videoFit: VideoFit { didSet { defaults.set(videoFit.rawValue, forKey: "videoFit") } }
    var fullScreenBehindDock: Bool { didSet { defaults.set(fullScreenBehindDock, forKey: "fullScreenBehindDock") } }
    var carSort: CarSort { didSet { defaults.set(carSort.rawValue, forKey: "carSort") } }

    // Playback
    var autoplayNext: Bool { didSet { defaults.set(autoplayNext, forKey: "autoplayNext") } }
    var resumePlayback: Bool { didSet { defaults.set(resumePlayback, forKey: "resumePlayback") } }
    var skipSeconds: Int { didSet { defaults.set(skipSeconds, forKey: "skipSeconds"); PlaybackController.shared.updateSkipIntervals() } }

    // YouTube
    var youTubeSite: YouTubeSite { didSet { defaults.set(youTubeSite.rawValue, forKey: "youTubeSite"); WebModel.resetAll() } }
    /// Size of the YouTube page on the car screen: 1.0 lays the page out at the screen's own pixel size.
    var youTubeZoom: Double { didSet { defaults.set(youTubeZoom, forKey: "youTubeZoom") } }
    var skipYouTubeAds: Bool { didSet { defaults.set(skipYouTubeAds, forKey: "skipYouTubeAds"); WebModel.resetAll() } }

    // Safety and the iPhone
    var hideVideoWhileDriving: Bool { didSet { defaults.set(hideVideoWhileDriving, forKey: "hideVideoWhileDriving"); DrivingMonitor.shared.update() } }
    var keepPhoneAwake: Bool { didSet { defaults.set(keepPhoneAwake, forKey: "keepPhoneAwake"); CarConnection.shared.applyPhoneSettings() } }
    var dimPhone: Bool { didSet { defaults.set(dimPhone, forKey: "dimPhone"); CarConnection.shared.applyPhoneSettings() } }

    // Phone library
    var librarySort: LibrarySort { didSet { defaults.set(librarySort.rawValue, forKey: "librarySort") } }
    var libraryFilter: LibraryFilter { didSet { defaults.set(libraryFilter.rawValue, forKey: "libraryFilter") } }
    /// Subfolder of the Files-app folder to show, or nil for everything.
    var libraryFolder: String? { didSet { defaults.set(libraryFolder, forKey: "libraryFolder") } }

    /// Automated CarPlay simulator test (launch argument `-CarVideoDemo YES`): walks through every car screen.
    let demoMode: Bool

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "fullScreenBehindDock": false,
            "autoplayNext": true,
            "resumePlayback": true,
            "skipSeconds": 10,
            "youTubeZoom": 1.25,
            "skipYouTubeAds": true,
            "hideVideoWhileDriving": true,
            "keepPhoneAwake": true,
            "dimPhone": false,
        ])
        videoFit = VideoFit(rawValue: d.string(forKey: "videoFit") ?? "") ?? .fit
        fullScreenBehindDock = d.bool(forKey: "fullScreenBehindDock")
        carSort = CarSort(rawValue: d.string(forKey: "carSort") ?? "") ?? .recentlyAdded
        autoplayNext = d.bool(forKey: "autoplayNext")
        resumePlayback = d.bool(forKey: "resumePlayback")
        skipSeconds = d.integer(forKey: "skipSeconds")
        youTubeSite = YouTubeSite(rawValue: d.string(forKey: "youTubeSite") ?? "") ?? .mobile
        youTubeZoom = d.double(forKey: "youTubeZoom")
        skipYouTubeAds = d.bool(forKey: "skipYouTubeAds")
        hideVideoWhileDriving = d.bool(forKey: "hideVideoWhileDriving")
        keepPhoneAwake = d.bool(forKey: "keepPhoneAwake")
        dimPhone = d.bool(forKey: "dimPhone")
        librarySort = LibrarySort(rawValue: d.string(forKey: "librarySort") ?? "") ?? .dateAddedNewest
        libraryFilter = LibraryFilter(rawValue: d.string(forKey: "libraryFilter") ?? "") ?? .all
        libraryFolder = d.string(forKey: "libraryFolder")
        demoMode = d.bool(forKey: "CarVideoDemo")
    }
}
