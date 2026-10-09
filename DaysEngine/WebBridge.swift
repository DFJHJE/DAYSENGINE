import Foundation
import SwiftUI
import UIKit
import WebKit

/// Shared state between the toolbar and the web view.
///
/// The launcher itself is HTML, so there is very little native state to hold: a reload counter
/// (bumping it makes the representable re-load the page), the last error the web view reported
/// — surfaced instead of leaving the user with a blank screen — and a weak reference to the
/// web view so the toolbar can present a share sheet anchored to it.
final class WebBridge: ObservableObject {
    @Published var reloadToken: Int = 0
    @Published var lastError: String?
    @Published var isLoading: Bool = false

    /// Assigned by `WebView.makeUIView`. Weak, because the view hierarchy owns the web view.
    weak var webView: WKWebView?

    func reload() {
        lastError = nil
        reloadToken &+= 1
    }

    /// Shares whatever the launcher is currently showing — how a user gets the page, or a
    /// diagnostic, out of the app sandbox.
    func presentShareSheet() {
        guard let webView = webView else { return }
        let url = webView.url ?? URL(string: "about:blank")!
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // iPad raises at presentation time without an anchor, so the popover must be configured.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = webView
            popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        WebBridge.presentOnTop(controller)
    }

    static func presentOnTop(_ controller: UIViewController) {
        guard let root = keyWindowRoot() else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }
}

/// The active window's root view controller, used for presenting UIKit controllers from SwiftUI.
func keyWindowRoot() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows where window.isKeyWindow {
            return window.rootViewController
        }
    }
    return UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
}
