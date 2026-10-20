import Observation
import UIKit
import WebKit

/// A long-lived YouTube web view and its state. There's one for the car screen and one for the iPhone
/// (where you sign in and type). They share cookies, so signing in on the phone signs in the car too.
@Observable
@MainActor
final class WebModel {
    static let car = WebModel(forCar: true)
    static let phone = WebModel(forCar: false)

    static func resetAll() {
        car.reset()
        phone.reset()
    }

    let forCar: Bool
    private(set) var webView: WKWebView?
    private(set) var canGoBack = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    /// Count of finished page loads, which the automated demo waits on.
    private(set) var finishedLoads = 0

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let delegate: WebDelegate

    private init(forCar: Bool) {
        self.forCar = forCar
        delegate = WebDelegate(forCar: forCar)
    }

    @discardableResult
    func ensureWebView(loading url: URL? = nil) -> WKWebView {
        if let webView {
            if let url { webView.load(URLRequest(url: url)) }
            return webView
        }
        let site = AppSettings.shared.youTubeSite
        let webView = WKWebView(frame: .zero, configuration: YouTube.configuration(forCar: forCar, messageHandler: delegate))
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        if site == .desktop {
            webView.customUserAgent = YouTube.desktopUserAgent
        }
        let isCar = forCar
        observations = [
            webView.observe(\.canGoBack, options: [.new]) { @Sendable _, _ in
                Task { @MainActor in WebModel.model(isCar).syncState() }
            },
            webView.observe(\.isLoading, options: [.new]) { @Sendable _, _ in
                Task { @MainActor in WebModel.model(isCar).syncState() }
            },
            webView.observe(\.url, options: [.new]) { @Sendable _, _ in
                Task { @MainActor in WebModel.model(isCar).syncState() }
            },
        ]
        self.webView = webView
        webView.load(URLRequest(url: url ?? YouTube.homeURL(site)))
        Diagnostics.log("Web", "Created \(forCar ? "car" : "phone") web view (\(site.rawValue) site)")
        return webView
    }

    fileprivate static func model(_ isCar: Bool) -> WebModel { isCar ? car : phone }

    fileprivate func syncState() {
        guard let webView else { return }
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if isLoading != webView.isLoading { isLoading = webView.isLoading }
        if currentURL != webView.url { currentURL = webView.url }
    }

    fileprivate func didFinish() {
        finishedLoads += 1
        syncState()
        if forCar, let url = webView?.url {
            Diagnostics.log("Web", "Car page loaded \(url.host ?? "")\(url.path)")
        }
    }

    func load(_ url: URL) {
        ensureWebView().load(URLRequest(url: url))
    }

    func goHome() {
        load(YouTube.homeURL(AppSettings.shared.youTubeSite))
    }

    func goBack() {
        webView?.goBack()
    }

    func reload() {
        webView?.reload()
    }

    func stopLoading() {
        webView?.stopLoading()
    }

    func pauseVideos() {
        webView?.evaluateJavaScript(YouTube.pauseVideosScript, completionHandler: nil)
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = YouTube.searchURL(trimmed, site: AppSettings.shared.youTubeSite) else { return }
        load(url)
    }

    /// Drops the web view so the next use builds one with the current settings.
    func reset() {
        guard let webView else { return }
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        observations = []
        self.webView = nil
        canGoBack = false
        currentURL = nil
    }

    fileprivate func contentProcessTerminated() {
        Diagnostics.log("Web", "\(forCar ? "Car" : "Phone") web content process ended; reloading")
        webView?.reload()
    }
}

/// Navigation and page callbacks, all on the main thread.
private final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let forCar: Bool

    init(forCar: Bool) {
        self.forCar = forCar
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let isCar = forCar
        MainActor.assumeIsolated { WebModel.model(isCar).didFinish() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Diagnostics.log("Web", "Load failed: \(message)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let message = error.localizedDescription
        Diagnostics.log("Web", "Couldn't open page: \(message)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let isCar = forCar
        MainActor.assumeIsolated { WebModel.model(isCar).contentProcessTerminated() }
    }

    /// Links that would open a new window open in the same one.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let request = navigationAction.request
        MainActor.assumeIsolated {
            if navigationAction.targetFrame == nil {
                webView.load(request)
            }
        }
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let name = message.name
        MainActor.assumeIsolated {
            if name == "carKeyboard" {
                CarUIState.shared.showKeyboard()
            }
        }
    }
}
