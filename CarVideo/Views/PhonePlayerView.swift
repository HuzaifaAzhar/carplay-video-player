import AVKit
import SwiftUI

/// Playback on the iPhone (when CarPlay isn't connected), using the system player with picture-in-picture,
/// subtitles and AirPlay.
struct PhonePlayerView: View {
    var body: some View {
        let playback = PlaybackController.shared
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Done") { playback.stop() }
                    .fontWeight(.semibold)
                Text(playback.current?.title ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                if CarConnection.shared.isConnected {
                    Button {
                        playback.moveToCar()
                        CarUIState.shared.screen = .player
                        CarUIState.shared.showControls()
                    } label: {
                        Label("CarPlay", systemImage: "car.fill")
                    }
                } else {
                    // Keeps the title centred.
                    Text("Done").fontWeight(.semibold).hidden()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .tint(.white)
            PlayerViewControllerRepresentable(player: playback.player)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
