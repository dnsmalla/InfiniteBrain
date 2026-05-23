import SwiftUI

/// Reusable Badge/Pill component for status indicators and counts.
public struct BadgeView: View {
    let text: String
    let icon: String?
    let color: Color
    
    public init(_ text: String, icon: String? = nil, color: Color = AppPalette.brand) {
        self.text = text
        self.icon = icon
        self.color = color
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption2.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Reusable Toggle for collapsible sidebars.
public struct SidebarToggle: View {
    @Binding var isCollapsed: Bool
    let direction: Edge
    
    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: iconName)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(AppPalette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
    }
    
    private var iconName: String {
        switch direction {
        case .leading: return isCollapsed ? "sidebar.left" : "arrow.left.to.line"
        case .trailing: return isCollapsed ? "sidebar.right" : "arrow.right.to.line"
        default: return "sidebar.left"
        }
    }
}

/// A dashed border view for placeholders and drop zones.
public struct PlaceholderOutline: View {
    let text: String
    let icon: String
    
    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AppPalette.surface.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppPalette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// Move FlowLayout here for shared usage.
public struct FlowLayout: Layout {
    let spacing: CGFloat
    public init(spacing: CGFloat = 8) { self.spacing = spacing }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var (rowW, rowH, totalH): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        var maxW: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if rowW + size.width > width {
                totalH += rowH + spacing; maxW = max(maxW, rowW); rowW = 0; rowH = 0
            }
            rowW += size.width + spacing; rowH = max(rowH, size.height)
        }
        totalH += rowH; maxW = max(maxW, rowW)
        return CGSize(width: min(width, maxW), height: totalH)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
