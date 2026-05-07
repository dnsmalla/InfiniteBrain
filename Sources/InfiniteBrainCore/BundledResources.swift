import Foundation

/// Public accessor for the skills/ and rules/ directories bundled inside
/// InfiniteBrainCore. Both the GUI app and the CLI rely on this so they
/// don't need to reach into `Bundle.module`, which is target-private.
public enum BundledResources {
    public static var skills: URL? {
        Bundle.module.url(forResource: "skills", withExtension: nil)
    }
    public static var rules: URL? {
        Bundle.module.url(forResource: "rules", withExtension: nil)
    }
    /// Folder containing the markdown preview template + KaTeX + marked
    /// assets. Used by the GUI's WKWebView.
    public static var web: URL? {
        Bundle.module.url(forResource: "web", withExtension: nil)
    }

    /// Resolves the skills directory to use: the user-edited copy in the
    /// vault sidecar if present, otherwise the bundled fallback.
    public static func skillsRoot(for vault: Vault) -> URL {
        if FileManager.default.fileExists(atPath: vault.skillsDir.path) {
            return vault.skillsDir
        }
        return skills ?? vault.skillsDir
    }
}
