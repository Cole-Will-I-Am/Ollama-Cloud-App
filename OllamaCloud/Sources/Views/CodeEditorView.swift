import SwiftUI
import WebKit

// MARK: - Language Detection

enum CodeLanguage {
    static func fromExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "py":                return "python"
        case "js", "jsx":        return "javascript"
        case "ts", "tsx":        return "typescript"
        case "swift":            return "swift"
        case "rs":               return "rust"
        case "go":               return "go"
        case "html", "htm":      return "html"
        case "css":              return "css"
        case "json":             return "json"
        case "md", "markdown":   return "markdown"
        case "yml", "yaml":      return "yaml"
        case "sh", "bash", "zsh": return "shell"
        case "java":             return "java"
        case "c", "h":           return "cpp"
        case "cpp", "cc", "cxx": return "cpp"
        case "rb":               return "python" // close enough highlighting
        case "xml", "svg":       return "html"
        case "sql":              return "sql"
        case "toml":             return "yaml"   // close enough
        default:                 return ""
        }
    }

    static func extensionForLanguage(_ lang: String) -> String {
        switch lang.lowercased() {
        case "python":              return "py"
        case "javascript":          return "js"
        case "typescript":          return "ts"
        case "swift":               return "swift"
        case "rust":                return "rs"
        case "go":                  return "go"
        case "html":                return "html"
        case "css":                 return "css"
        case "json":                return "json"
        case "shell", "bash":       return "sh"
        case "java":                return "java"
        case "cpp", "c++":          return "cpp"
        case "sql":                 return "sql"
        case "yaml":                return "yml"
        default:                    return "txt"
        }
    }
}

// MARK: - CodeEditorView

#if os(iOS)
struct CodeEditorView: UIViewRepresentable {
    let content: String
    let language: String
    let onContentChange: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = makeWebViewConfig(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.isReady = false
        context.coordinator.pendingContent = content
        context.coordinator.pendingLanguage = language
        webView.loadHTMLString(Self.editorHTML(language: language), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.isReady else {
            coordinator.pendingContent = content
            coordinator.pendingLanguage = language
            return
        }

        if coordinator.lastSetContent != content {
            coordinator.lastSetContent = content
            let escaped = content.jsEscaped
            webView.evaluateJavaScript("setContent(\(escaped))") { _, _ in }
        }
        if coordinator.lastSetLanguage != language {
            coordinator.lastSetLanguage = language
            let escaped = language.jsEscaped
            webView.evaluateJavaScript("setLanguage(\(escaped))") { _, _ in }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onContentChange: onContentChange)
    }
}
#endif

#if os(macOS)
struct CodeEditorView: NSViewRepresentable {
    let content: String
    let language: String
    let onContentChange: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = makeWebViewConfig(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.isReady = false
        context.coordinator.pendingContent = content
        context.coordinator.pendingLanguage = language
        webView.loadHTMLString(Self.editorHTML(language: language), baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.isReady else {
            coordinator.pendingContent = content
            coordinator.pendingLanguage = language
            return
        }

        if coordinator.lastSetContent != content {
            coordinator.lastSetContent = content
            let escaped = content.jsEscaped
            webView.evaluateJavaScript("setContent(\(escaped))") { _, _ in }
        }
        if coordinator.lastSetLanguage != language {
            coordinator.lastSetLanguage = language
            let escaped = language.jsEscaped
            webView.evaluateJavaScript("setLanguage(\(escaped))") { _, _ in }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onContentChange: onContentChange)
    }
}
#endif

// MARK: - Shared

extension CodeEditorView {
    func makeWebViewConfig(coordinator: Coordinator) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let userContent = config.userContentController
        userContent.add(coordinator, name: "contentChanged")
        userContent.add(coordinator, name: "editorReady")
        return config
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onContentChange: (String) -> Void
        var isReady = false
        var pendingContent: String?
        var pendingLanguage: String?
        var lastSetContent: String?
        var lastSetLanguage: String?
        weak var webView: WKWebView?

        init(onContentChange: @escaping (String) -> Void) {
            self.onContentChange = onContentChange
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Don't push content here — module scripts haven't loaded yet.
            // Wait for the "editorReady" message from the JS module.
            self.webView = webView
        }

        func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .other { return .allow }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            loadFallbackEditor(in: webView, error: error)
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            loadFallbackEditor(in: webView, error: error)
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "editorReady" {
                isReady = true
                guard let webView else { return }
                if let content = pendingContent {
                    lastSetContent = content
                    let escaped = content.jsEscaped
                    webView.evaluateJavaScript("setContent(\(escaped))") { _, _ in }
                    pendingContent = nil
                }
                if let lang = pendingLanguage {
                    lastSetLanguage = lang
                    let escaped = lang.jsEscaped
                    webView.evaluateJavaScript("setLanguage(\(escaped))") { _, _ in }
                    pendingLanguage = nil
                }
                return
            }

            guard message.name == "contentChanged",
                  let body = message.body as? String else { return }
            lastSetContent = body
            onContentChange(body)
        }

        private func loadFallbackEditor(in webView: WKWebView, error: Error) {
            isReady = false
            let escapedError = error.localizedDescription
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <style>
                html, body {
                  margin: 0;
                  padding: 0;
                  background: #080810;
                  color: rgba(255,255,255,0.92);
                  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                .container {
                  min-height: 100vh;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  text-align: center;
                  padding: 24px;
                }
                .card {
                  max-width: 520px;
                  background: #131319;
                  border: 1px solid rgba(255,255,255,0.08);
                  border-radius: 12px;
                  padding: 16px;
                }
                .title { font-size: 14px; margin-bottom: 8px; }
                .detail { color: rgba(255,255,255,0.45); font-size: 12px; }
              </style>
              <script>
                window.setContent = function() {};
                window.setLanguage = function() {};
              </script>
            </head>
            <body>
              <div class="container">
                <div class="card">
                  <div class="title">Code editor failed to load.</div>
                  <div class="detail">Check network access and retry opening this file.<br>\(escapedError)</div>
                </div>
              </div>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    static func editorHTML(language: String) -> String {
        let escapedLanguage = language.jsEscaped
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { height: 100%; background: #080810; overflow: hidden; }
          body {
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            color: #f4f4ff;
          }
          .wrap {
            height: 100%;
            display: flex;
            flex-direction: column;
            border-top: 1px solid #101020;
          }
          .bar {
            flex: 0 0 auto;
            display: flex;
            justify-content: flex-end;
            align-items: center;
            height: 26px;
            padding: 0 8px;
            background: #0a0a14;
            border-bottom: 1px solid #151530;
          }
          .badge {
            font-size: 10px;
            letter-spacing: 0.08em;
            color: #7f7fb3;
            text-transform: uppercase;
          }
          #editor {
            flex: 1 1 auto;
            width: 100%;
            height: 100%;
            resize: none;
            border: 0;
            outline: none;
            padding: 12px;
            background: #080810;
            color: #f4f4ff;
            font-size: 13px;
            line-height: 1.45;
            tab-size: 2;
            caret-color: #8888cc;
            white-space: pre;
            overflow: auto;
          }
          #editor::selection {
            background: #1a1a3e;
          }
        </style>
        <script>
          let textarea = null;
          let badge = null;
          let debounceTimer = null;

          function updateLanguageBadge(lang) {
            if (!badge) return;
            const normalized = (lang || "").trim();
            badge.textContent = normalized.length > 0 ? normalized : "text";
          }

          window.setContent = function(text) {
            if (!textarea) return;
            const next = String(text || "");
            if (textarea.value !== next) {
              textarea.value = next;
            }
          };

          window.setLanguage = function(lang) {
            updateLanguageBadge(String(lang || ""));
          };

          window.addEventListener("DOMContentLoaded", () => {
            textarea = document.getElementById("editor");
            badge = document.getElementById("langBadge");

            if (!textarea) {
              window.webkit.messageHandlers.editorReady.postMessage("ok");
              return;
            }

            textarea.addEventListener("input", () => {
              if (debounceTimer) clearTimeout(debounceTimer);
              debounceTimer = setTimeout(() => {
                window.webkit.messageHandlers.contentChanged.postMessage(textarea.value);
              }, 300);
            });

            updateLanguageBadge(\(escapedLanguage));
            window.webkit.messageHandlers.editorReady.postMessage("ok");
          });
        </script>
        </head>
        <body>
          <div class="wrap">
            <div class="bar"><span id="langBadge" class="badge">text</span></div>
            <textarea id="editor" spellcheck="false" autocapitalize="off" autocomplete="off" autocorrect="off"></textarea>
          </div>
        </body>
        </html>
        """
    }
}

// MARK: - JS String Escaping

private extension String {
    var jsEscaped: String {
        let data = try? JSONEncoder().encode(self)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
