import UIKit
import WebKit

/// YouTube's website in a web view: addresses, the browser identity it's loaded with, and the scripts
/// injected into it.
enum YouTube {
    static func homeURL(_ site: YouTubeSite) -> URL {
        URL(string: site == .mobile ? "https://m.youtube.com/" : "https://www.youtube.com/")!
    }

    static func searchURL(_ query: String, site: YouTubeSite) -> URL? {
        var components = URLComponents(url: homeURL(site), resolvingAgainstBaseURL: false)
        components?.path = "/results"
        components?.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components?.url
    }

    static func watchURL(id: String, site: YouTubeSite) -> URL? {
        var components = URLComponents(url: homeURL(site), resolvingAgainstBaseURL: false)
        components?.path = "/watch"
        components?.queryItems = [URLQueryItem(name: "v", value: id)]
        return components?.url
    }

    static func isYouTube(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    /// The video ID in any common YouTube link: watch?v=, youtu.be/, /shorts/, /embed/, /live/.
    static func videoID(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isYouTube(url) else { return nil }
        if url.host?.lowercased() == "youtu.be" {
            return url.pathComponents.dropFirst().first
        }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        let parts = url.pathComponents
        if let marker = parts.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }), marker + 1 < parts.count {
            return parts[marker + 1]
        }
        return nil
    }

    /// A YouTube page to open for a pasted or shared link, on the site the user chose.
    static func pageURL(for text: String, site: YouTubeSite) -> URL? {
        if let id = videoID(in: text) { return watchURL(id: id, site: site) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), isYouTube(url) { return url }
        return nil
    }

    @MainActor
    static func configuration(forCar: Bool, messageHandler: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let settings = AppSettings.shared
        let configuration = WKWebViewConfiguration()
        // Play inside the page; the system's full-screen player wouldn't appear on the car screen.
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if settings.youTubeSite == .mobile {
            let major = UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "17"
            configuration.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"
        }
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: hideAppPromptsScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if settings.skipYouTubeAds {
            controller.addUserScript(WKUserScript(source: skipAdsScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        if forCar {
            controller.addUserScript(WKUserScript(source: carKeyboardScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            controller.add(messageHandler, name: "carKeyboard")
        }
        return configuration
    }

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// Hides "Open App" buttons and banners, which can't do anything here.
    static let hideAppPromptsScript = """
    (function () {
      var css = '.open-app-button, ytm-mealbar-promo-renderer, .mealbar-promo-renderer, ytm-app-promo-renderer, \
    .ytm-app-promo, ytm-upsell-dialog-renderer, ytd-mealbar-promo-renderer { display: none !important; }';
      var style = document.createElement('style');
      style.textContent = css;
      (document.head || document.documentElement).appendChild(style);
    })();
    """

    /// Skips or fast-forwards video ads and removes ad slots from lists. Restores sound and speed afterwards.
    static let skipAdsScript = """
    (function () {
      if (window.__carVideoAdSkip) return;
      window.__carVideoAdSkip = true;
      var touched = false;
      setInterval(function () {
        try {
          var player = document.querySelector('.html5-video-player, #movie_player');
          var video = document.querySelector('video');
          var ad = player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting'));
          if (ad && video) {
            touched = true;
            video.muted = true;
            if (isFinite(video.duration) && video.duration > 0) { video.currentTime = video.duration; }
          } else if (touched && video) {
            touched = false;
            video.muted = false;
          }
          document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, .ytm-skip-ad-button')
            .forEach(function (b) { b.click(); });
          document.querySelectorAll('ytm-promoted-sparkles-web-renderer, ytm-companion-ad-renderer, ad-slot-renderer, \
    ytm-ad-slot-renderer, ytm-promoted-video-renderer, ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer')
            .forEach(function (e) { e.remove(); });
        } catch (e) {}
      }, 400);
    })();
    """

    /// CarPlay has no keyboard for web pages, so typing into the page opens the app's own car keyboard.
    static let carKeyboardScript = """
    (function () {
      document.addEventListener('focusin', function (e) {
        var t = e.target;
        if (!t || !t.matches) return;
        if (t.matches('input[type=search], input[type=text], input:not([type]), textarea, [contenteditable=true]')) {
          t.blur();
          window.webkit.messageHandlers.carKeyboard.postMessage('show');
        }
      }, true);
    })();
    """

    static let pauseVideosScript = "document.querySelectorAll('video').forEach(function (v) { v.pause(); });"

    static func scrollScript(pages: Double) -> String {
        "window.scrollBy({ top: window.innerHeight * \(pages) * 0.8, behavior: 'smooth' });"
    }
}
