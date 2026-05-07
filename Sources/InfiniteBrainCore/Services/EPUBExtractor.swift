import Foundation

/// Extracts plain text from an EPUB. EPUB is a ZIP archive containing
/// XHTML chapters and an OPF manifest that lists their reading order.
/// We unzip via `/usr/bin/unzip` (always present on macOS), find the
/// OPF via META-INF/container.xml, walk the spine in order, and strip
/// the HTML to text.
public struct EPUBExtractor: Sendable {
    public init() {}

    public func extract(_ url: URL) throws -> String {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("ib-epub-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", "-q", url.path, "-d", tmp.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "EPUBExtractor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "unzip failed for \(url.lastPathComponent)"])
        }

        // Find the OPF path via the container manifest.
        let containerURL = tmp.appendingPathComponent("META-INF/container.xml")
        let containerXML = (try? String(contentsOf: containerURL, encoding: .utf8)) ?? ""
        guard let opfPath = Self.firstMatch(in: containerXML, pattern: #"full-path="([^"]+)""#) else {
            throw NSError(domain: "EPUBExtractor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "no OPF path in container.xml"])
        }
        let opfURL = tmp.appendingPathComponent(opfPath)
        let opfDir = opfURL.deletingLastPathComponent()
        guard let opfXML = try? String(contentsOf: opfURL, encoding: .utf8) else {
            throw NSError(domain: "EPUBExtractor", code: 3)
        }

        // Build manifest: id → href.
        var manifest: [String: String] = [:]
        let itemRE = try NSRegularExpression(pattern: #"<item\s+([^>]+)/?>"#)
        let opfNS = opfXML as NSString
        for m in itemRE.matches(in: opfXML, range: NSRange(location: 0, length: opfNS.length)) {
            let attrs = opfNS.substring(with: m.range(at: 1))
            if let id   = Self.firstMatch(in: attrs, pattern: #"id="([^"]+)""#),
               let href = Self.firstMatch(in: attrs, pattern: #"href="([^"]+)""#) {
                manifest[id] = href
            }
        }

        // Spine: ordered list of idrefs.
        var spine: [String] = []
        let spineRE = try NSRegularExpression(pattern: #"<itemref\s+([^>]+)/?>"#)
        for m in spineRE.matches(in: opfXML, range: NSRange(location: 0, length: opfNS.length)) {
            let attrs = opfNS.substring(with: m.range(at: 1))
            if let idref = Self.firstMatch(in: attrs, pattern: #"idref="([^"]+)""#) {
                spine.append(idref)
            }
        }

        // Walk spine; strip each chapter's HTML to text.
        var out = ""
        for idref in spine {
            guard let href = manifest[idref] else { continue }
            // hrefs may be percent-encoded.
            let normalized = href.removingPercentEncoding ?? href
            let chapterURL = opfDir.appendingPathComponent(normalized)
            guard let html = try? String(contentsOf: chapterURL, encoding: .utf8) else { continue }
            out += Self.stripHTML(html) + "\n\n"
        }
        return out
    }

    // MARK: - Helpers

    static func firstMatch(in s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Strip HTML to plain text. Preserves paragraph breaks at block-level
    /// tags, drops scripts/styles, decodes the common entities. Good enough
    /// for downstream atomize-text — the AI handles minor noise.
    static func stripHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>",
                                   with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",
                                   with: "", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->",
                                   with: "", options: .regularExpression)
        // Block tags → paragraph break.
        s = s.replacingOccurrences(of: "</(p|div|section|article|h[1-6]|li|tr|td|th|blockquote)>",
                                   with: "\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<br\\s*/?\\s*>",
                                   with: "\n", options: [.regularExpression, .caseInsensitive])
        // Remaining tags.
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        // Collapse runs of blank lines.
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">",
        "&quot;": "\"", "&apos;": "'", "&nbsp;": " ",
        "&ndash;": "–", "&mdash;": "—",
        "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}",
        "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
        "&hellip;": "…", "&copy;": "©", "&reg;": "®", "&trade;": "™",
    ]

    static func decodeEntities(_ input: String) -> String {
        var s = input
        for (k, v) in namedEntities { s = s.replacingOccurrences(of: k, with: v) }
        // &#1234; (decimal) and &#x4E2D; (hex)
        s = s.replacingOccurrences(of: #"&#x([0-9a-fA-F]+);"#, with: "", options: .regularExpression) {
            UInt32($0, radix: 16).flatMap(UnicodeScalar.init).map { String($0) } ?? ""
        }
        s = s.replacingOccurrences(of: #"&#(\d+);"#, with: "", options: .regularExpression) {
            UInt32($0).flatMap(UnicodeScalar.init).map { String($0) } ?? ""
        }
        return s
    }
}

private extension String {
    /// Variant of `replacingOccurrences(of:with:options:)` that lets you
    /// transform each captured group instead of using a static replacement.
    /// We need this for numeric HTML entities — `Foundation` doesn't expose
    /// a regex callback so we walk matches by hand.
    func replacingOccurrences(of pattern: String,
                              with placeholder: String,
                              options: String.CompareOptions,
                              _ transform: (String) -> String) -> String {
        guard options.contains(.regularExpression),
              let re = try? NSRegularExpression(pattern: pattern) else { return self }
        let ns = self as NSString
        let matches = re.matches(in: self, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return self }
        var out = ""
        var cursor = 0
        for m in matches {
            let full = m.range
            if full.location > cursor {
                out += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            let group = m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : ""
            out += transform(group)
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            out += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        _ = placeholder // silence unused param; kept for API symmetry
        return out
    }
}
