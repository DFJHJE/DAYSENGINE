import SwiftUI
import UIKit
import WebKit

/// A `WKWebView` that runs the launcher and reports what it rendered.
///
/// Three settings are load-bearing:
///   * `mediaTypesRequiringUserActionForPlayback = []` — without it Web Audio stays muted until
///     a tap, and the launcher's music would look broken.
///   * `allowingReadAccessTo: documentsURL` — the user picks `.GPK` files through the page's own
///     file input; the read grant is what lets the picker reach them.
///   * an opaque background, because the page is dark and WKWebView defaults to white, which
///     flashes on every load.
struct WebView: UIViewRepresentable {
    @EnvironmentObject var bridge: WebBridge

    /// Notifications used to drive the launch self-check; see `SceneDelegate`.
    static let didFinishNotification = Notification.Name("DaysEngineWebViewDidFinish")
    static let didFailNotification = Notification.Name("DaysEngineWebViewDidFail")

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Let the page make sound without waiting for a tap.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true

        // The launcher keeps its UI state (volumes, the archive key) in localStorage.
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "launcher")
        configuration.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.059, green: 0.059, blue: 0.102, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.scrollView.bounces = false
        // The page is already mobile-first; letting it scale keeps iPad layouts honest.
        view.allowsBackForwardNavigationGestures = false

        // A software keyboard would cover the key field; the launcher only needs hex here.
        view.customUserAgent = nil

        context.coordinator.webView = view
        bridge.webView = view
        context.coordinator.load()
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        // A bump of `reloadToken` is the toolbar's way of asking for a reload.
        if context.coordinator.lastReloadToken != bridge.reloadToken {
            context.coordinator.lastReloadToken = bridge.reloadToken
            context.coordinator.load()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let bridge: WebBridge
        weak var webView: WKWebView?
        var lastReloadToken: Int = 0
        private(set) var isLoading: Bool?

        init(bridge: WebBridge) {
            self.bridge = bridge
        }

        // ------------------------------------------------------------ loading

        @discardableResult
        func load() -> Bool {
            guard let webView = webView else { return false }
            guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") else {
                let message = "应用内没有找到 www/index.html — 构建时网页资源没有被打包进去。"
                bridge.lastError = message
                NSLog("DaysEngine: \(message)")
                return false
            }

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            // Read access is granted to Documents as a whole so the page's file picker can reach
            // the user's .GPK files, which is also what the Info.plist file-sharing keys expose.
            if let documents = documents {
                webView.loadFileURL(index, allowingReadAccessTo: documents)
            } else {
                webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
            }
            return true
        }

        // ------------------------------------------------------------ navigation

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            bridge.isLoading = false
            bridge.lastError = nil
            NotificationCenter.default.post(name: WebView.didFinishNotification, object: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            bridge.isLoading = false
            bridge.lastError = error.localizedDescription
            NSLog("DaysEngine: navigation failed: \(error.localizedDescription)")
            NotificationCenter.default.post(name: WebView.didFailNotification, object: error)
        }

        /// Keep the launcher inside the app; send anything else to Safari.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let isLocal = url.isFileURL || url.scheme == "about"
            if isLocal || navigationAction.targetFrame == nil {
                decisionHandler(url.isFileURL ? .allow : .cancel)
                if !isLocal && UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
                return
            }

            decisionHandler(.cancel)
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }

        /// The page uses a plain `<input type="file">`; there is nothing to intercept.
        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "DaysEngine", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            present(alert)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "DaysEngine", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            present(alert)
        }

        private func present(_ controller: UIViewController) {
            WebBridge.presentOnTop(controller)
        }

        // ------------------------------------------------------------ page messages

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "launcher" else { return }
            if let text = message.body as? String {
                NSLog("DaysEngine page: \(text)")
            }
        }

        /// The Documents directory, so the Files app and iTunes file sharing can top it up.
        static var documentsURL: URL? {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
    }
}
