import SwiftUI

/// Full-screen video on the car screen. Tap to show or hide the controls; they hide on their own after
/// a few seconds of playback.
struct CarPlayerView: View {
    let metrics: CarMetrics

    var body: some View {
        let playback = PlaybackController.shared
        let ui = CarUIState.shared
        let settings = AppSettings.shared

        ZStack {
            Color.black
            PlayerLayerRepresentable(player: playback.player, fit: settings.videoFit)
                .modifier(FullBleed(enabled: settings.fullScreenBehindDock))
            if DrivingMonitor.shared.hidesVideo {
                DrivingCover(metrics: metrics)
            }
            if playback.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
            if ui.controlsVisible || !playback.isPlaying || playback.errorMessage != nil {
                CarPlayerControls(metrics: metrics)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { ui.toggleControls() }
        .animation(.easeInOut(duration: 0.2), value: ui.controlsVisible)
    }
}

/// Lets the picture extend under the CarPlay dock when the user prefers size over a clear edge.
struct FullBleed: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

struct CarPlayerControls: View {
    let metrics: CarMetrics

    var body: some View {
        let playback = PlaybackController.shared
        let ui = CarUIState.shared
        let settings = AppSettings.shared
        let skip = settings.skipSeconds

        VStack(spacing: metrics.gap) {
            HStack(spacing: metrics.gap) {
                CarIconButton(systemName: "chevron.backward", size: metrics.button) { ui.closePlayer() }
                VStack(alignment: .leading, spacing: 0) {
                    Text(playback.current?.title ?? "")
                        .font(.system(size: metrics.bodyFont, weight: .semibold))
                        .lineLimit(1)
                    if let error = playback.errorMessage {
                        Text(error)
                            .font(.system(size: metrics.captionFont))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                CarIconButton(systemName: settings.videoFit == .fit ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                              size: metrics.button) {
                    settings.videoFit = settings.videoFit == .fit ? .fill : .fit
                    ui.showControls()
                }
                Button {
                    playback.cycleSpeed()
                    ui.showControls()
                } label: {
                    Text(speedText(playback.rate))
                        .font(.system(size: metrics.bodyFont, weight: .bold).monospacedDigit())
                        .frame(minWidth: metrics.button, minHeight: metrics.button)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                .buttonStyle(CarPressStyle())
                CarIconButton(systemName: "play.rectangle.fill", size: metrics.button, background: Color(red: 0.86, green: 0.08, blue: 0.1)) {
                    ui.openYouTube()
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: metrics.gap * 2.5) {
                CarIconButton(systemName: "backward.end.fill", size: metrics.button) {
                    playback.previous()
                    ui.showControls()
                }
                CarIconButton(systemName: Self.skipSymbol(back: true, seconds: skip), size: metrics.button) {
                    playback.skip(by: -Double(skip))
                    ui.showControls()
                }
                CarIconButton(systemName: playback.isPlaying ? "pause.fill" : "play.fill", size: metrics.bigButton,
                              background: .white, foreground: .black) {
                    playback.togglePlayPause()
                    ui.showControls()
                }
                CarIconButton(systemName: Self.skipSymbol(back: false, seconds: skip), size: metrics.button) {
                    playback.skip(by: Double(skip))
                    ui.showControls()
                }
                CarIconButton(systemName: "forward.end.fill", size: metrics.button) {
                    playback.next()
                    ui.showControls()
                }
                .opacity(playback.hasNext ? 1 : 0.35)
                .disabled(!playback.hasNext)
            }

            Spacer(minLength: 0)

            HStack(spacing: metrics.gap) {
                Text(playback.currentTime.clockText)
                CarScrubber(metrics: metrics)
                Text("-" + max(0, playback.duration - playback.currentTime).clockText)
            }
            .font(.system(size: metrics.captionFont, weight: .semibold).monospacedDigit())
        }
        .padding(metrics.gap)
        .background(
            LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private func speedText(_ rate: Float) -> String {
        rate == 1 ? "1×" : String(format: "%g×", rate)
    }

    /// SF Symbols only has skip icons for 5, 10, 15, 30, 45, 60, 75 and 90 seconds.
    static func skipSymbol(back: Bool, seconds: Int) -> String {
        let available = [5, 10, 15, 30, 45, 60, 75, 90]
        let name = back ? "gobackward" : "goforward"
        return available.contains(seconds) ? "\(name).\(seconds)" : name
    }
}

/// The position bar. Touching anywhere on it jumps there; dragging scrubs (on cars that report drags).
struct CarScrubber: View {
    let metrics: CarMetrics
    @State private var dragFraction: Double?

    var body: some View {
        let playback = PlaybackController.shared
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let played = playback.duration > 0 ? playback.currentTime / playback.duration : 0
            let fraction = clamp(dragFraction ?? played, 0, 1)
            let knob = metrics.captionFont * 1.2
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 5)
                Capsule().fill(.white).frame(width: width * fraction, height: 5)
                Circle().fill(.white)
                    .frame(width: knob, height: knob)
                    .offset(x: width * fraction - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragFraction = clamp(value.location.x / width, 0, 1)
                    CarUIState.shared.showControls()
                }
                .onEnded { value in
                    let target = clamp(value.location.x / width, 0, 1)
                    dragFraction = target
                    playback.seek(toFraction: target)
                    // Hold the new position until the player reports it, so the bar doesn't jump back.
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        dragFraction = nil
                    }
                })
        }
        .frame(height: metrics.button)
    }
}
