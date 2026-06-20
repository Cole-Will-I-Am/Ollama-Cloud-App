import Foundation
import WebKit
#if os(iOS)
import UIKit
#endif

/// Renders Markdown to a polished, paginated PDF — the native analogue of the
/// manticthink website's print-to-PDF document export. The Markdown is rendered
/// to HTML inside an offscreen WKWebView (reusing the bundled `marked` renderer
/// and the SEER document stylesheet), then captured as a PDF:
///   • iOS  — `UIPrintPageRenderer` → real multi-page US-Letter pages.
///   • macOS — `WKWebView.createPDF`.
@MainActor
final class PDFExporter: NSObject {
    static let shared = PDFExporter()

    /// Build a PDF for the given Markdown and return a temp-file URL (nil on failure).
    func makePDF(markdown: String, title: String) async -> URL? {
        let html = Self.buildHTML(markdown: markdown, title: title)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        let coordinator = LoadCoordinator()
        web.navigationDelegate = coordinator
        web.loadHTMLString(html, baseURL: nil)

        let loaded = await waitForLoad(coordinator, timeout: 8.0)
        guard loaded else { return nil }
        // Let fonts/marked finish laying out before snapshotting.
        try? await Task.sleep(nanoseconds: 250_000_000)

        guard let data = await pdfData(from: web), !data.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.safeFilename(title) + ".pdf")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    // MARK: - Load (with timeout)

    private func waitForLoad(_ coordinator: LoadCoordinator, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await coordinator.wait() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    // MARK: - Capture

    #if os(iOS)
    private func pdfData(from web: WKWebView) async -> Data? {
        let pageW: CGFloat = 612, pageH: CGFloat = 792, margin: CGFloat = 36 // US Letter @72dpi, 0.5" margin
        let paper = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let printable = paper.insetBy(dx: margin, dy: margin)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        // UIPrintPageRenderer exposes these only via KVC.
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(printable, forKey: "printableRect")
        let out = NSMutableData()
        UIGraphicsBeginPDFContextToData(out, paper, nil)
        let pages = max(renderer.numberOfPages, 1)
        for i in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: paper)
        }
        UIGraphicsEndPDFContext()
        return out as Data
    }
    #else
    private func pdfData(from web: WKWebView) async -> Data? {
        await withCheckedContinuation { cont in
            web.createPDF(configuration: WKPDFConfiguration()) { result in
                switch result {
                case .success(let data): cont.resume(returning: data)
                case .failure: cont.resume(returning: nil)
                }
            }
        }
    }
    #endif

    // MARK: - HTML

    private static func buildHTML(markdown: String, title: String) -> String {
        let safe = escapeHTML(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "SEER document" : title)
        let b64 = Data(markdown.utf8).base64EncodedString()
        let decode = "new TextDecoder().decode(Uint8Array.from(atob(\"\(b64)\"), function(c){return c.charCodeAt(0);}))"

        let renderScript: String
        if let marked = loadMarkedJS()?.replacingOccurrences(of: "</script", with: "<\\/script") {
            renderScript = """
            <script>\(marked)</script>
            <script>
            (function(){
              try { document.getElementById('out').innerHTML = marked.parse(\(decode)); }
              catch (e) { var p = document.createElement('pre'); p.textContent = \(decode); document.getElementById('out').appendChild(p); }
            })();
            </script>
            """
        } else {
            // Fallback if the renderer didn't bundle: show the raw Markdown as text.
            renderScript = """
            <script>
            (function(){ var p = document.createElement('pre'); p.textContent = \(decode); document.getElementById('out').appendChild(p); })();
            </script>
            """
        }

        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(safe)</title>
        <style>\(PDF_CSS)</style></head>
        <body><header class="pdf-head"><span class="pdf-brand">SEER</span><span class="pdf-title">\(safe)</span></header>
        <main id="out"></main>
        \(renderScript)
        </body></html>
        """
    }

    private static func loadMarkedJS() -> String? {
        guard let url = Bundle.main.url(forResource: "marked.umd", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func safeFilename(_ title: String) -> String {
        let base = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = (base.isEmpty ? "SEER document" : base)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        return String(cleaned.prefix(60))
    }

    private static let PDF_CSS = """
      @page { margin: 18mm 16mm; }
      * { box-sizing: border-box; }
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        color: #16181d; line-height: 1.6; font-size: 12pt; margin: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      .pdf-head { display: flex; align-items: baseline; gap: 12px; border-bottom: 2px solid #6179ff;
        padding-bottom: 10px; margin-bottom: 22px; }
      .pdf-brand { font-weight: 700; letter-spacing: 0.12em; color: #6179ff; font-size: 13pt; }
      .pdf-title { font-weight: 600; font-size: 11pt; color: #5a606b; }
      main h1, main h2, main h3, main h4 { line-height: 1.3; font-weight: 600; margin: 1.1em 0 0.5em; page-break-after: avoid; }
      main h1 { font-size: 1.7em; } main h2 { font-size: 1.35em; } main h3 { font-size: 1.15em; }
      main h1:first-child { margin-top: 0; }
      main p { margin: 0.6em 0; }
      main ul, main ol { margin: 0.6em 0; padding-left: 1.5em; }
      main li { margin: 0.3em 0; }
      main a { color: #3651d6; }
      main blockquote { margin: 0.8em 0; padding: 4px 0 4px 14px; border-left: 3px solid #6179ff; color: #5a606b; }
      main hr { border: none; border-top: 1px solid #d7dae0; margin: 1.3em 0; }
      main code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.85em;
        background: #f0f1f4; padding: 1.5px 5px; border-radius: 4px; }
      main pre { background: #f6f7f9; border: 1px solid #e2e4e9; border-radius: 8px; padding: 12px 14px;
        overflow-x: auto; page-break-inside: avoid; white-space: pre-wrap; word-wrap: break-word; }
      main pre code { background: none; padding: 0; font-size: 0.82em; line-height: 1.5; }
      main table { border-collapse: collapse; margin: 0.8em 0; width: 100%; page-break-inside: avoid; }
      main th, main td { border: 1px solid #d7dae0; padding: 6px 10px; text-align: left; font-size: 0.92em; }
      main th { background: #f0f1f4; font-weight: 600; }
      main img, main svg { max-width: 100%; height: auto; }
    """

    /// Navigation delegate that resolves once the offscreen page finishes (or fails) loading.
    private final class LoadCoordinator: NSObject, WKNavigationDelegate {
        private var cont: CheckedContinuation<Bool, Never>?
        private var settled = false

        func wait() async -> Bool {
            await withCheckedContinuation { c in
                if settled { c.resume(returning: true) } else { self.cont = c }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }

        private func finish(_ ok: Bool) {
            guard !settled else { return }
            settled = true
            cont?.resume(returning: ok)
            cont = nil
        }
    }
}
