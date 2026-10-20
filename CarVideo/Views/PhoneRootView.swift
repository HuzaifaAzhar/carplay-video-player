import SwiftUI

/// The iPhone app: videos, YouTube (sign in, search with a real keyboard, send to the car) and settings.
struct PhoneRootView: View {
    @State private var tab = 0

    var body: some View {
        let playback = PlaybackController.shared
        TabView(selection: $tab) {
            LibraryView()
                .modifier(NowPlayingInset())
                .tabItem { Label("Videos", systemImage: "film.stack") }
                .tag(0)
            PhoneYouTubeView()
                .tabItem { Label("YouTube", systemImage: "play.rectangle.fill") }
                .tag(1)
            SettingsView()
                .modifier(NowPlayingInset())
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .fullScreenCover(isPresented: Binding(
            get: { playback.output == .phone && playback.current != nil },
            set: { presented in
                if !presented, playback.output == .phone { playback.stop() }
            }
        )) {
            PhonePlayerView()
        }
    }
}

/// Remote controls for what's playing on the car screen, along the bottom of the iPhone app.
struct NowPlayingInset: ViewModifier {
    func body(content: Content) -> some View {
        let playback = PlaybackController.shared
        content.safeAreaInset(edge: .bottom) {
            if playback.output == .car, let current = playback.current {
                CarRemoteBar(item: current)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }
        }
    }
}

struct CarRemoteBar: View {
    let item: VideoItem

    var body: some View {
        let playback = PlaybackController.shared
        let skip = AppSettings.shared.skipSeconds
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ThumbnailView(item: item)
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Label("Playing on CarPlay", systemImage: "car.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { playback.skip(by: -Double(skip)) } label: {
                    Image(systemName: CarPlayerControls.skipSymbol(back: true, seconds: skip))
                }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 32)
                }
                Button { playback.skip(by: Double(skip)) } label: {
                    Image(systemName: CarPlayerControls.skipSymbol(back: false, seconds: skip))
                }
                Button {
                    CarUIState.shared.closePlayer()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            .font(.title3)
            .buttonStyle(.plain)
            ProgressView(value: playback.duration > 0 ? min(playback.currentTime / playback.duration, 1) : 0)
                .tint(.accentColor)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
