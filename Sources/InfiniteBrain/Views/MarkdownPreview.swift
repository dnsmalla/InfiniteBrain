import SwiftUI
import WebKit
import InfiniteBrainCore

/// Renders a markdown document inside a WKWebView using bundled marked.js
/// (markdown → HTML) + KaTeX (LaTeX math typesetting) + a GitHub-flavoured
/// CSS file. Everything is offline — assets live under
/// `InfiniteBrainCore/Resources/web/`.
///
/// Frontmatter (`---…---`) is stripped before rendering so the user sees a
/// clean reading view.
struct MarkdownPreview: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "ready")
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")  // transparent
        context.coordinator.webView = view
        loadTemplate(into: view)
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingMarkdown = MarkdownPreview.stripFrontmatter(markdown)
        context.coordinator.flushIfReady()
    }

    /// Loads the bundled `preview.html` so KaTeX/marked/CSS load via
    /// relative paths. WKWebView needs an explicit `allowingReadAccessTo`
    /// URL to load sibling resources from disk.
    private func loadTemplate(into view: WKWebView) {
        guard let webRoot = BundledResources.web,
              let htmlURL = webRoot.appendingPathComponent("preview.html") as URL?,
              FileManager.default.fileExists(atPath: htmlURL.path) else {
            view.loadHTMLString("<p>Preview template missing.</p>", baseURL: nil)
            return
        }
        view.loadFileURL(htmlURL, allowingReadAccessTo: webRoot)
    }

    // MARK: - Frontmatter

    /// Removes a leading `---\n…\n---\n` block. Returns the rest as-is.
    static func stripFrontmatter(_ s: String) -> String {
        guard s.hasPrefix("---\n") else { return s }
        let after = s.dropFirst(4)
        guard let end = after.range(of: "\n---\n") else { return s }
        return String(after[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Coordinator

    /// Holds the WKWebView reference, listens for the `ready` message from
    /// the page, and forwards the markdown body via evaluateJavaScript.
    /// Has to be a class so it can be both NSObject (for delegates) and
    /// hold mutable state across view updates.
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingMarkdown: String = ""
        private var pageReady = false

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "ready" {
                pageReady = true
                flushIfReady()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Some load paths skip the `ready` postMessage; fall back to
            // a small delay after didFinish so the script has executed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pageReady = true
                self?.flushIfReady()
            }
        }

        func flushIfReady() {
            guard pageReady, let webView else { return }
            // JSON-encode the markdown so newlines and quotes don't break
            // the JS literal. Using JSONEncoder for one string handles the
            // edge cases for free.
            guard let data = try? JSONEncoder().encode(pendingMarkdown),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.renderMarkdown && window.renderMarkdown(\(json));", completionHandler: nil)
        }
    }
}
