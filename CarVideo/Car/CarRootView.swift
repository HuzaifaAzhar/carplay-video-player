import SwiftUI

/// Root of the car screen. Everything is laid out inside the safe area, which keeps it clear of the
/// CarPlay dock and status bar; only the video itself may go behind them (a setting).
struct CarRootView: View {
    var body: some View {
        let ui = CarUIState.shared
        GeometryReader { geo in
            let metrics = CarMetrics(size: geo.size)
            ZStack {
                switch ui.screen {
                case .home:
                    CarHomeView(metrics: metrics)
                case .player:
                    CarPlayerView(metrics: metrics)
                case .youtube:
                    CarYouTubeView(metrics: metrics)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: ui.screen)
    }
}

/// A round icon button sized for a car touchscreen.
struct CarIconButton: View {
    let systemName: String
    let size: CGFloat
    var background: Color = .white.opacity(0.16)
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(CarPressStyle())
    }
}

/// A capsule button with an icon and a label.
struct CarPillButton: View {
    let title: String
    let systemName: String
    let metrics: CarMetrics
    var background: Color = .white.opacity(0.16)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.gap * 0.6) {
                Image(systemName: systemName)
                    .font(.system(size: metrics.bodyFont, weight: .semibold))
                Text(title)
                    .font(.system(size: metrics.bodyFont, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, metrics.gap * 1.3)
            .frame(height: metrics.button)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(CarPressStyle())
    }
}

/// Visible press feedback, since there's no hover or haptics in the car.
struct CarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// Shown over video while the car is moving (if that setting is on).
struct DrivingCover: View {
    let metrics: CarMetrics

    var body: some View {
        VStack(spacing: metrics.gap) {
            Image(systemName: "car.side.fill")
                .font(.system(size: metrics.bigButton * 0.5))
            Text("Video hidden while driving")
                .font(.system(size: metrics.titleFont, weight: .bold))
            Text("Sound keeps playing. It comes back when the car stops. You can change this in Car Video's settings on the iPhone.")
                .font(.system(size: metrics.captionFont))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(metrics.gap * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
