import SwiftUI

/// Standardised professional palette for InfiniteBrain.
/// Focuses on Apple-style premium aesthetics: glassmorphism, thin borders, and 
/// refined indigo/slate accents.
public enum AppPalette {
    /// Primary brand color — a deep, sophisticated indigo.
    public static let brand = Color(red: 0.36, green: 0.38, blue: 0.95)
    
    /// Sidebar background with semantic system integration.
    public static let sidebarBackground = Color(NSColor.windowBackgroundColor).opacity(0.8)
    
    /// Surface color for cards and panels.
    public static let surface = Color(NSColor.controlBackgroundColor)
    
    /// Substrate color for main text areas.
    public static let textBackground = Color(NSColor.textBackgroundColor)
    
    /// Subtle border color for separator lines.
    public static let border = Color.primary.opacity(0.1)
    
    /// Secondary prominence text/icons.
    public static let secondaryBrand = Color.indigo.opacity(0.8)
    
    /// Success indicator (e.g. drafted sections).
    public static let success = Color.green
    
    /// Error/Destructive indicator.
    public static let error = Color.red
    
    /// Tertiary/Disabled state.
    public static let tertiary = Color.secondary.opacity(0.5)

    /// Background gradient for headers.
    public static let headerGradient = LinearGradient(
        colors: [brand.opacity(0.15), .clear],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension View {
    func glassmorphicCard() -> some View {
        self.padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    func cardStyle() -> some View {
        self.padding()
            .background(AppPalette.surface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.border, lineWidth: 1))
    }
}
