import SwiftUI

/// YouTube on the iPhone: sign in, search with the real keyboard, and send what you found to the car.
struct PhoneYouTubeView: View {
    var body: some View {
        let web = WebModel.phone
        let car = CarConnection.shared
        NavigationStack {
            Group {
                if let webView = web.webView {
                    WebViewRepresentable(webView: webView)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear { web.ensureWebView() }
            .navigationTitle("YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.first ?? ""
                        Task { @MainActor in PhoneYouTubeView.openPasted(text) }
                    }
                    .labelStyle(.iconOnly)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { web.goBack() } label: { Image(systemName: "chevron.backward") }
                        .disabled(!web.canGoBack)
                    Button { web.goHome() } label: { Image(systemName: "house") }
                    Button { web.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    Button {
                        guard let url = web.currentURL else { return }
                        web.pauseVideos()
                        CarUIState.shared.openYouTube(url: url)
                    } label: {
                        Label("Play on CarPlay", systemImage: "car.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(!car.isConnected || web.currentURL == nil)
                }
            }
        }
    }

    /// A pasted YouTube link opens on the car screen when connected, otherwise here.
    @MainActor
    static func openPasted(_ text: String) {
        guard let page = YouTube.pageURL(for: text, site: AppSettings.shared.youTubeSite) else { return }
        if CarConnection.shared.isConnected {
            CarUIState.shared.openYouTube(url: page)
        } else {
            WebModel.phone.load(page)
        }
    }
}
