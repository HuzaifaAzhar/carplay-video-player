import SwiftUI

/// YouTube's website on the car screen, laid out at the screen's real resolution (see `ScaledWebContainer`),
/// with a small floating toolbar: close, back, home, search and reload. UIKit adds its own CarPlay scroll
/// arrows to the page, for cars that don't report swipes.
struct CarYouTubeView: View {
    let metrics: CarMetrics

    var body: some View {
        let ui = CarUIState.shared
        let web = WebModel.car

        ZStack(alignment: .topLeading) {
            if let webView = web.webView {
                ScaledWebView(webView: webView, zoom: AppSettings.shared.youTubeZoom)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if DrivingMonitor.shared.hidesVideo {
                DrivingCover(metrics: metrics)
            }
            toolbar
                .padding(metrics.gap * 0.6)
            if ui.keyboardVisible {
                CarKeyboardView(metrics: metrics)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ui.keyboardVisible)
        .animation(.easeInOut(duration: 0.2), value: ui.toolbarExpanded)
    }

    @ViewBuilder
    private var toolbar: some View {
        let ui = CarUIState.shared
        let web = WebModel.car
        let size = metrics.button * 0.9
        if ui.toolbarExpanded {
            HStack(spacing: metrics.gap * 0.6) {
                CarIconButton(systemName: "xmark", size: size) { ui.closeYouTube() }
                CarIconButton(systemName: "chevron.backward", size: size) {
                    web.goBack()
                    ui.expandToolbar()
                }
                .opacity(web.canGoBack ? 1 : 0.35)
                CarIconButton(systemName: "house.fill", size: size) {
                    web.goHome()
                    ui.expandToolbar()
                }
                CarIconButton(systemName: "magnifyingglass", size: size) { ui.showKeyboard() }
                CarIconButton(systemName: web.isLoading ? "xmark.circle" : "arrow.clockwise", size: size) {
                    if web.isLoading { web.stopLoading() } else { web.reload() }
                    ui.expandToolbar()
                }
                CarIconButton(systemName: "chevron.left.2", size: size) { ui.collapseToolbar() }
            }
            .padding(metrics.gap * 0.4)
            .background(Capsule().fill(.black.opacity(0.6)))
        } else {
            CarIconButton(systemName: "line.3.horizontal", size: size, background: .black.opacity(0.6)) { ui.expandToolbar() }
        }
    }
}
