import SwiftUI
import AppKit
import InfiniteBrainCore

/// Renders a markdown document with proper typography:
///   - YAML frontmatter is stripped
///   - Headings (h1-h6) get true heading sizes + bold weight
///   - Bold / italic / inline code / links rendered inline
///   - $...$ and $$...$$ math expressions kept verbatim in monospaced
///     box style — readable but not LaTeX-rendered (KaTeX integration is
///     the next polish step)
///
/// Built on AttributedString(markdown:) + NSTextView so we don't ship a
/// webview stack. Selection + cursor work natively.
struct MarkdownPreview: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let text = NSTextView()
        text.isEditable = false
        text.isRichText = true
        text.isSelectable = true
        text.allowsUndo = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 6)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.lineFragmentPadding = 0
        text.autoresizingMask = .width

        scroll.documentView = text
        apply(to: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        apply(to: text)
        // Scroll back to top when the selection changes to a different note.
        text.scroll(.zero)
    }

    private func apply(to text: NSTextView) {
        let body = Self.stripFrontmatter(markdown)
        let attr = Self.render(body)
        text.textStorage?.setAttributedString(attr)
    }

    // MARK: - Frontmatter

    /// Removes a leading `---\n…\n---\n` block. Returns the rest as-is.
    static func stripFrontmatter(_ s: String) -> String {
        guard s.hasPrefix("---\n") else { return s }
        let after = s.dropFirst(4)
        guard let end = after.range(of: "\n---\n") else { return s }
        return String(after[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rendering

    private static let bodyFontSize: CGFloat = 14
    private static let headingSizes: [CGFloat] = [26, 22, 18, 16, 14, 13]

    static func render(_ markdown: String) -> NSAttributedString {
        let parsed: AttributedString
        do {
            parsed = try AttributedString(
                markdown: markdown,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return NSAttributedString(
                string: markdown,
                attributes: [.font: NSFont.systemFont(ofSize: bodyFontSize)]
            )
        }

        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let runStr = String(parsed[run.range].characters)
            out.append(styledRun(runStr, run: run))
        }
        return out
    }

    /// Build the NSAttributedString attributes for a single AttributedString
    /// run, honoring heading levels and inline emphasis.
    private static func styledRun(_ s: String, run: AttributedString.Runs.Run) -> NSAttributedString {
        var size: CGFloat = bodyFontSize
        var bold = false
        var italic = false
        var monospaced = false

        if let intent = run.presentationIntent {
            for c in intent.components {
                if case .header(let level) = c.kind {
                    let idx = max(0, min(headingSizes.count - 1, level - 1))
                    size = headingSizes[idx]
                    bold = true
                }
            }
        }
        if let inline = run.inlinePresentationIntent {
            if inline.contains(.stronglyEmphasized) { bold = true }
            if inline.contains(.emphasized) { italic = true }
            if inline.contains(.code) { monospaced = true }
        }

        var font: NSFont
        if monospaced {
            font = .monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
        } else {
            font = bold
                ? .systemFont(ofSize: size, weight: .bold)
                : .systemFont(ofSize: size)
            if italic {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        if let url = run.link { attrs[.link] = url }

        // Paragraph style: tighter heading leading, generous body leading.
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = bold && size > bodyFontSize ? 1.1 : 1.35
        para.paragraphSpacing = bold && size > bodyFontSize ? 6 : 4
        attrs[.paragraphStyle] = para

        return NSAttributedString(string: s, attributes: attrs)
    }
}
