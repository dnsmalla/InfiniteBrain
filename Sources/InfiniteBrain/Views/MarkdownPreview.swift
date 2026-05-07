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
        // Pre-process math so AttributedString treats $...$ and $$...$$ as
        // inline code, which renders monospaced. Saves bundling KaTeX and at
        // least makes the equations visually distinct from prose.
        let prepared = wrapMath(markdown)

        let parsed: AttributedString
        do {
            parsed = try AttributedString(
                markdown: prepared,
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
        var lastBlockIdentity: Int? = nil
        for run in parsed.runs {
            // Block-level transition? Insert a paragraph break so headings
            // don't jam into the next paragraph and adjacent paragraphs
            // actually look separate.
            let identity = run.presentationIntent?.components.first?.identity
            if let last = lastBlockIdentity, identity != last {
                out.append(NSAttributedString(string: "\n\n"))
            }
            lastBlockIdentity = identity

            let runStr = String(parsed[run.range].characters)
            out.append(styledRun(runStr, run: run))
        }
        return out
    }

    /// Rewrites `$$expr$$` and `$expr$` as `` `$$expr$$` `` and `` `$expr$` ``
    /// so the markdown parser surfaces them as inline code. Conservative
    /// scan — bails out on multi-line math or unbalanced delimiters.
    static func wrapMath(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "$" && (i == 0 || chars[i - 1] != "\\") {
                // $$ block?
                if i + 1 < chars.count, chars[i + 1] == "$" {
                    if let end = findRange(chars, of: ["$", "$"], from: i + 2),
                       !chars[(i + 2)..<end].contains("\n") {
                        let inside = String(chars[(i + 2)..<end])
                        if !inside.isEmpty {
                            out += "`$$\(inside)$$`"
                            i = end + 2
                            continue
                        }
                    }
                } else if let end = findIndex(chars, of: "$", from: i + 1),
                          !chars[(i + 1)..<end].contains("\n") {
                    let inside = String(chars[(i + 1)..<end])
                    if !inside.isEmpty {
                        out += "`$\(inside)$`"
                        i = end + 1
                        continue
                    }
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    private static func findIndex(_ chars: [Character], of c: Character, from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i] == c && (i == 0 || chars[i - 1] != "\\") { return i }
            i += 1
        }
        return nil
    }

    private static func findRange(_ chars: [Character], of seq: [Character], from start: Int) -> Int? {
        guard !seq.isEmpty else { return nil }
        var i = start
        while i + seq.count <= chars.count {
            var match = true
            for j in 0..<seq.count where chars[i + j] != seq[j] { match = false; break }
            if match { return i }
            i += 1
        }
        return nil
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
