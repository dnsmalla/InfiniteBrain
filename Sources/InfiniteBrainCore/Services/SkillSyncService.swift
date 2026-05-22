import Foundation

/// Ensures that the vault's local skill directory is synchronized with the 
/// internal application bundle skills. This ensures that new features (like 
/// drafting) are available even in older vaults.
public struct SkillSyncService {
    public static func sync(to vault: Vault) {
        guard let bundleSkills = Bundle.module.url(forResource: "skills", withExtension: nil) else {
            return
        }
        
        let fm = FileManager.default
        let dest = vault.skillsDir
        
        // Ensure destination exists
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        
        guard let items = try? fm.contentsOfDirectory(at: bundleSkills, includingPropertiesForKeys: nil) else {
            return
        }
        
        for item in items {
            let itemName = item.lastPathComponent
            let target = dest.appendingPathComponent(itemName)
            
            // If it doesn't exist, copy it.
            // If it exists, we could check versions, but for now we'll just 
            // ensure it exists. Professional research tools should allow 
            // user-defined skills to override, so we only copy if MISSING.
            if !fm.fileExists(atPath: target.path) {
                try? fm.copyItem(at: item, to: target)
            } else {
                // Check if the SKILL.md file is inside.
                let skillFile = target.appendingPathComponent("SKILL.md")
                if !fm.fileExists(atPath: skillFile.path) {
                    try? fm.copyItem(at: item, to: target)
                }
            }
        }
    }
}
