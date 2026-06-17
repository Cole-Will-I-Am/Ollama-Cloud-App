import SwiftUI
import WebKit

#if os(iOS)
struct HTMLContentView: UIViewRepresentable {
    let htmlContent: String
    /// Reports the rendered content height so the container can size to it
    /// (avoids vertical clipping). Horizontal overflow is handled by scrolling.
    var onHeight: ((CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Let the user pan/scroll inside the visual (wide tables, tall charts).
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.showsVerticalScrollIndicator = true
        webView.scrollView.showsHorizontalScrollIndicator = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeight = onHeight
        guard context.coordinator.loadedContent != htmlContent else { return }
        context.coordinator.loadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onHeight: onHeight) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedContent: String?
        var onHeight: ((CGFloat) -> Void)?
        init(onHeight: ((CGFloat) -> Void)?) { self.onHeight = onHeight }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .other { return .allow }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.body.scrollHeight)") { [weak self] value, _ in
                if let num = value as? NSNumber { self?.onHeight?(CGFloat(num.doubleValue)) }
            }
        }
    }
}
#endif

#if os(macOS)
struct HTMLContentView: NSViewRepresentable {
    let htmlContent: String
    var onHeight: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeight = onHeight
        guard context.coordinator.loadedContent != htmlContent else { return }
        context.coordinator.loadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onHeight: onHeight) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedContent: String?
        var onHeight: ((CGFloat) -> Void)?
        init(onHeight: ((CGFloat) -> Void)?) { self.onHeight = onHeight }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .other { return .allow }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.body.scrollHeight)") { [weak self] value, _ in
                if let num = value as? NSNumber { self?.onHeight?(CGFloat(num.doubleValue)) }
            }
        }
    }
}
#endif
