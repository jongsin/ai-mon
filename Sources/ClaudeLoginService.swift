import AppKit
import WebKit

/// Opens an in-app Claude login window (WKWebView). Once the user logs in,
/// the `sessionKey` cookie is captured automatically from the web view's
/// cookie store and returned — no DevTools or AppleScript required.
///
/// OAuth providers (e.g. "Continue with Google") open a popup via
/// `window.open`; WKWebView ignores those unless a `WKUIDelegate` creates the
/// child web view. We honor them with a real popup window that shares the same
/// configuration, so cookies and `window.opener`/`postMessage` work.
final class ClaudeLoginController: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = ClaudeLoginController()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var popupWindow: NSWindow?
    private var popupWebView: WKWebView?
    private var pollTimer: Timer?
    private var onComplete: ((String?) -> Void)?
    private var captured = false

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    /// Clears the in-app browser's Claude session (full logout), so the next
    /// connect starts from the real login page — lets you switch accounts or
    /// re-authenticate (e.g. via "Continue with Google").
    static func clearSession(completion: (() -> Void)? = nil) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let targets = records.filter { rec in
                let name = rec.displayName.lowercased()
                return name.contains("claude.ai") || name.contains("anthropic")
            }
            store.removeData(ofTypes: types, for: targets) {
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    /// Presents the login window. `onComplete` is called with the captured
    /// sessionKey on success, or `nil` if the user closed the window first.
    func start(onComplete: @escaping (String?) -> Void) {
        // If a login window is already open, just bring it forward.
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        self.onComplete = onComplete
        self.captured = false

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true // allow OAuth popups

        let frame = NSRect(x: 0, y: 0, width: 520, height: 720)
        let web = WKWebView(frame: frame, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        // Present as a normal desktop browser so claude.ai serves the full login UI.
        web.customUserAgent = userAgent
        self.webView = web

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Claude 로그인 — 로그인하면 자동으로 연동돼요"
        w.center()
        w.contentView = web
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.level = .floating
        self.window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        if let url = URL(string: "https://claude.ai/login") {
            web.load(URLRequest(url: url))
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let t = pollTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func poll() {
        guard !captured, let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            guard let self = self, !self.captured else { return }
            if let cookie = cookies.first(where: { $0.name == "sessionKey" }),
               cookie.value.hasPrefix("sk-ant") {
                self.captured = true
                DispatchQueue.main.async { self.finish(with: cookie.value) }
            }
        }
    }

    private func finish(with key: String?) {
        pollTimer?.invalidate()
        pollTimer = nil
        closePopup()
        let callback = onComplete
        onComplete = nil
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        callback?(key)
    }

    private func closePopup() {
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }

    // MARK: - WKNavigationDelegate

    // Re-check cookies as soon as a navigation completes (faster than waiting
    // for the next poll tick after the post-login redirect).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        poll()
    }

    // MARK: - WKUIDelegate (OAuth popups)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Honor window.open by creating a real popup that shares the opener's
        // configuration (same data store / process pool → cookies + opener work).
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.customUserAgent = userAgent
        self.popupWebView = popup

        let pw = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        pw.title = "로그인"
        pw.center()
        pw.contentView = popup
        pw.isReleasedWhenClosed = false
        pw.level = .floating
        self.popupWindow = pw
        pw.makeKeyAndOrderFront(nil)
        return popup
    }

    // The popup called window.close() (OAuth finished) — tear it down and
    // re-check for the session cookie.
    func webViewDidClose(_ webView: WKWebView) {
        if webView == popupWebView {
            closePopup()
            poll()
        }
    }

    // MARK: - NSWindowDelegate

    // User closed the main login window before logging in.
    func windowWillClose(_ notification: Notification) {
        guard !captured else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        closePopup()
        let callback = onComplete
        onComplete = nil
        window = nil
        webView = nil
        callback?(nil)
    }
}
