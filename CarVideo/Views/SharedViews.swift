import AVFoundation
import SwiftUI
import UIKit
import WebKit

/// A video's thumbnail, filled into whatever frame it's given.
struct ThumbnailView: View {
    let item: VideoItem
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image = image ?? ThumbnailStore.shared.cached(item) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.isStream ? "link" : "film")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .task(id: item.id) {
            image = await ThumbnailStore.shared.thumbnail(for: item)
        }
    }
}

/// A view whose layer is an `AVPlayerLayer`.
final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

/// Shows the shared player. Creating a new player layer moves the picture to it, which is how video
/// moves between the iPhone and the car screen.
struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer
    let fit: VideoFit

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        let gravity: AVLayerVideoGravity = fit == .fill ? .resizeAspectFill : .resizeAspect
        if view.playerLayer.videoGravity != gravity {
            view.playerLayer.videoGravity = gravity
        }
    }

    static func dismantleUIView(_ view: PlayerLayerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

/// Holds a web view at the car screen's own resolution and scales it down to fit. iOS hands the car window
/// a point size (a 1280×720 screen can come through as about 467×263 pt), and a page laid out for that
/// would look like a phone page and crop video. Laid out at the pixel size instead, one page pixel lands on
/// one screen pixel. `zoom` above 1 makes the page bigger (fewer page pixels per screen). On very wide
/// screens the page is kept to about 1100 px wide, where YouTube's layout and text still work.
final class ScaledWebContainer: UIView {
    private(set) var webView: WKWebView
    var zoom: CGFloat = 1 {
        didSet { if oldValue != zoom { setNeedsLayout() } }
    }
    private var loggedSize: CGSize = .zero
    private static let maxPageWidth: CGFloat = 1100

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func attach(_ newWebView: WKWebView) {
        guard newWebView !== webView || webView.superview !== self else { return }
        if webView.superview === self { webView.removeFromSuperview() }
        webView = newWebView
        addSubview(newWebView)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let area = bounds
        guard area.width > 0, area.height > 0 else { return }
        let scale = max(1, traitCollection.displayScale)
        let factor = max(clamp(zoom, 0.5, 3), area.width * scale / Self.maxPageWidth)
        let page = CGSize(width: (area.width * scale / factor).rounded(), height: (area.height * scale / factor).rounded())
        webView.transform = .identity
        webView.bounds = CGRect(origin: .zero, size: page)
        webView.center = CGPoint(x: area.midX, y: area.midY)
        webView.transform = CGAffineTransform(scaleX: area.width / page.width, y: area.height / page.height)
        if page != loggedSize {
            loggedSize = page
            Diagnostics.log("Web", "Car page area \(area.size.text) pt at @\(scale)x → page \(page.text) (zoom \(String(format: "%.2f", factor)))")
        }
    }
}

struct ScaledWebView: UIViewRepresentable {
    let webView: WKWebView
    let zoom: Double

    func makeUIView(context: Context) -> ScaledWebContainer {
        ScaledWebContainer(webView: webView)
    }

    func updateUIView(_ view: ScaledWebContainer, context: Context) {
        view.attach(webView)
        view.zoom = CGFloat(zoom)
    }
}

/// A plain web view, for the iPhone.
struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
