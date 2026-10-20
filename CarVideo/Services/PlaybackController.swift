import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// One shared player for the car screen and the iPhone. Saves where you stopped in each video, publishes
/// Now Playing info and answers the car's steering-wheel and media buttons.
@Observable
@MainActor
final class PlaybackController {
    static let shared = PlaybackController()

    /// Where the video is being shown.
    enum Output: String {
        case none, phone, car
    }

    let player = AVPlayer()
    private(set) var current: VideoItem?
    /// The list the video was started from, for next/previous and autoplay.
    private(set) var queue: [VideoItem] = []
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var rate: Float = 1
    private(set) var errorMessage: String?
    var output: Output = .none

    @ObservationIgnored private var configured = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var lastSavedAt = Date.distantPast
    @ObservationIgnored private var artworkItemId: String?

    private init() {}

    static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 2]

    var hasNext: Bool { index.map { $0 + 1 < queue.count } ?? false }
    var hasPrevious: Bool { index.map { $0 > 0 } ?? false }
    private var index: Int? { current.flatMap { item in queue.firstIndex { $0.id == item.id } } }

    // MARK: - Setup

    func configure() {
        guard !configured else { return }
        configured = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause
        setupObservers()
        setupRemoteCommands()
    }

    private func setupObservers() {
        observations.append(player.observe(\.timeControlStatus, options: [.new]) { @Sendable _, _ in
            Task { @MainActor in PlaybackController.shared.syncState() }
        })
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { @Sendable time in
            let seconds = time.seconds
            MainActor.assumeIsolated { PlaybackController.shared.tick(seconds) }
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { @Sendable note in
            let item = (note.object as? AVPlayerItem).map { ObjectIdentifier($0) }
            MainActor.assumeIsolated { PlaybackController.shared.itemEnded(item) }
        })
        tokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) { @Sendable note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            MainActor.assumeIsolated { PlaybackController.shared.failed(message ?? "Playback failed.") }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { @Sendable note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                // Headphones or the car's audio went away: pause rather than play out of the phone.
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    PlaybackController.shared.pause()
                }
            }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { @Sendable note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                if type == AVAudioSession.InterruptionType.ended.rawValue,
                   let options, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    PlaybackController.shared.resume()
                }
            }
        })
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in
            MainActor.assumeIsolated { PlaybackController.shared.resume() }
            return .success
        }
        c.pauseCommand.addTarget { _ in
            MainActor.assumeIsolated { PlaybackController.shared.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { _ in
            MainActor.assumeIsolated { PlaybackController.shared.togglePlayPause() }
            return .success
        }
        c.nextTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { PlaybackController.shared.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { PlaybackController.shared.previous() }
            return .success
        }
        c.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            MainActor.assumeIsolated { PlaybackController.shared.skip(by: interval) }
            return .success
        }
        c.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            MainActor.assumeIsolated { PlaybackController.shared.skip(by: -interval) }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { PlaybackController.shared.seek(to: position) }
            return .success
        }
        updateSkipIntervals()
    }

    func updateSkipIntervals() {
        let seconds = NSNumber(value: AppSettings.shared.skipSeconds)
        MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [seconds]
        MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [seconds]
    }

    // MARK: - Transport

    func play(_ item: VideoItem, in list: [VideoItem], on output: Output) {
        saveProgress()
        errorMessage = nil
        current = item
        queue = list.contains(where: { $0.id == item.id }) ? list : [item]
        self.output = output
        let start = resumePoint(for: item)
        player.replaceCurrentItem(with: AVPlayerItem(url: item.url))
        if start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        currentTime = start
        duration = item.duration ?? 0
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: rate)
        VideoLibrary.shared.markPlayed(id: item.id)
        lastSavedAt = Date()
        updateNowPlaying()
        Diagnostics.log("Player", "Playing \"\(item.title)\" on \(output.rawValue) from \(start.clockText)")
    }

    private func resumePoint(for item: VideoItem) -> Double {
        guard AppSettings.shared.resumePlayback, !item.watched, item.position > 5 else { return 0 }
        if let duration = item.duration, duration > 0, item.position > duration - 10 { return 0 }
        return item.position
    }

    /// Moves what's playing on the iPhone to the car screen.
    func moveToCar() {
        guard current != nil else { return }
        output = .car
        Diagnostics.log("Player", "Moved playback to the car screen")
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func pause() {
        player.pause()
        saveProgress()
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        if duration > 0, currentTime >= duration - 0.5 {
            seek(to: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.playImmediately(atRate: rate)
        updateNowPlaying()
    }

    func stop() {
        saveProgress()
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        queue = []
        output = .none
        isPlaying = false
        currentTime = 0
        duration = 0
        errorMessage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artworkItemId = nil
    }

    func seek(to seconds: Double) {
        guard current != nil else { return }
        let target = max(0, duration > 0 ? min(seconds, duration) : seconds)
        seeking = true
        currentTime = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { @Sendable _ in
            Task { @MainActor in
                PlaybackController.shared.seeking = false
                PlaybackController.shared.updateNowPlaying()
            }
        }
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        seek(to: duration * min(max(fraction, 0), 1))
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func next() {
        guard let index, index + 1 < queue.count else { return }
        play(queue[index + 1], in: queue, on: output == .none ? .phone : output)
    }

    func previous() {
        // Like a music player: restart unless we're near the start.
        if currentTime > 5 || !hasPrevious {
            seek(to: 0)
            return
        }
        guard let index else { return }
        play(queue[index - 1], in: queue, on: output == .none ? .phone : output)
    }

    func cycleSpeed() {
        let speeds = Self.speeds
        let next = speeds[((speeds.firstIndex(of: rate) ?? 1) + 1) % speeds.count]
        rate = next
        if isPlaying { player.rate = next }
        updateNowPlaying()
    }

    func carDisconnected() {
        guard output == .car else { return }
        pause()
        Diagnostics.log("Player", "Car disconnected, paused")
    }

    // MARK: - State

    private func syncState() {
        let status = player.timeControlStatus
        let playing = status != .paused
        if playing != isPlaying { isPlaying = playing }
        let buffering = status == .waitingToPlayAtSpecifiedRate
        if buffering != isBuffering { isBuffering = buffering }
        if let error = player.currentItem?.error {
            failed(error.localizedDescription)
        }
        updateNowPlaying()
    }

    private func tick(_ seconds: Double) {
        guard current != nil else { return }
        if !seeking, seconds.isFinite { currentTime = seconds }
        if let itemDuration = player.currentItem?.duration, itemDuration.isNumeric, itemDuration.seconds > 0,
           abs(itemDuration.seconds - duration) > 0.5 {
            duration = itemDuration.seconds
            updateNowPlaying()
        }
        if isPlaying, Date().timeIntervalSince(lastSavedAt) > 5 {
            saveProgress()
        }
    }

    func saveProgress() {
        guard let current, currentTime > 0 else { return }
        lastSavedAt = Date()
        VideoLibrary.shared.updatePosition(id: current.id, position: currentTime, duration: duration > 0 ? duration : nil)
    }

    private func itemEnded(_ item: ObjectIdentifier?) {
        guard let playerItem = player.currentItem, item == ObjectIdentifier(playerItem), let current else { return }
        VideoLibrary.shared.updatePosition(id: current.id, position: duration, duration: duration)
        VideoLibrary.shared.setWatched(id: current.id, true)
        Diagnostics.log("Player", "Finished \"\(current.title)\"")
        if AppSettings.shared.autoplayNext, hasNext {
            next()
        } else {
            isPlaying = false
            updateNowPlaying()
        }
    }

    private func failed(_ message: String) {
        guard errorMessage != message else { return }
        errorMessage = message
        Diagnostics.log("Player", "Error: \(message)")
    }

    // MARK: - Now Playing

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork], artworkItemId == current.id {
            info[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if artworkItemId != current.id {
            artworkItemId = current.id
            let item = current
            Task {
                guard let image = await ThumbnailStore.shared.thumbnail(for: item), self.current?.id == item.id else { return }
                var withArt = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                withArt[MPMediaItemPropertyArtwork] = Self.artwork(image)
                MPNowPlayingInfoCenter.default().nowPlayingInfo = withArt
            }
        }
    }

    /// Built outside the main actor: the system calls the image handler on a background queue.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
