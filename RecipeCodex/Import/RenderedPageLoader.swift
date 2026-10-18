import Capture
import UIKit
import WebKit

/// The rendered DOM and where the page ended up.
struct RenderedPage: Sendable {
    var html: String
    var url: URL
}

/// Renders a page in a WKWebView the cook never sees, so a JavaScript-built page (ChefSteps' Next.js
/// shell) arrives the way the Share Extension gets it from Safari: as the rendered DOM.
///
/// The view sits beneath the window's content rather than detached: WebKit treats a web view that is
/// in no window as hidden and may hold back its timers and animation frames, which client-rendered
/// pages wait on. It uses a non-persistent data store, so nothing the page stores outlives the import.
@MainActor
final class RenderedPageLoader: NSObject, WKNavigationDelegate {
    /// How long to wait for the page to load.
    static let loadTimeout: Duration = .seconds(20)
    /// After the load finishes, how long scripts get to build the recipe.
    static let settleTimeout: Duration = .seconds(10)
    private static let pollInterval: Duration = .milliseconds(500)

    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, any Error>?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        webView.customUserAgent = WebPageFetcher.safariUserAgent
        webView.isUserInteractionEnabled = false
        webView.accessibilityElementsHidden = true
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads `url`, then reads `document.documentElement.outerHTML` until `isReady` accepts it or the
    /// settle time runs out, and returns the last reading. Throws when the page doesn't load.
    static func render(_ url: URL, isReady: (RenderedPage) async -> Bool) async throws -> RenderedPage {
        let loader = RenderedPageLoader()
        loader.attach()
        defer { loader.detach() }
        return try await loader.render(url, isReady: isReady)
    }

    private func render(_ url: URL, isReady: (RenderedPage) async -> Bool) async throws -> RenderedPage {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.load(url) }
            group.addTask {
                try await Task.sleep(for: Self.loadTimeout)
                throw WebImportError.network("The page took too long to load.")
            }
            defer { group.cancelAll() }
            try await group.next()
        }

        var page = try await currentPage(fallback: url)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.settleTimeout)
        while !(await isReady(page)), clock.now < deadline {
            try await Task.sleep(for: Self.pollInterval)
            page = try await currentPage(fallback: url)
        }
        return page
    }

    private func load(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                loadContinuation = continuation
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                webView.load(request)
            }
        } onCancel: {
            Task { @MainActor in self.finishLoad(.failure(CancellationError())) }
        }
    }

    private func currentPage(fallback: URL) async throws -> RenderedPage {
        let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
        return RenderedPage(html: html, url: webView.url ?? fallback)
    }

    private func finishLoad(_ result: Result<Void, any Error>) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if case .failure = result { webView.stopLoading() }
        continuation.resume(with: result)
    }

    // MARK: - Window

    private func attach() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        // Beneath everything the window shows, so it renders but is covered.
        window?.insertSubview(webView, at: 0)
    }

    private func detach() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.removeFromSuperview()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishLoad(.failure(WebImportError.network(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finishLoad(.failure(WebImportError.network(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        // The same refusals the fetcher reports (403, 404) end the render with the same wording.
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            finishLoad(.failure(WebImportError.httpStatus(response.statusCode)))
            return .cancel
        }
        return .allow
    }
}
