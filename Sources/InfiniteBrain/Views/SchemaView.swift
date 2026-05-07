import SwiftUI
import InfiniteBrainCore

/// Reference card for the Infinite Brain architecture: 16 node types
/// and 10 semantic edges. Lets the user verify that the system follows
/// the spec and see where each type fits.
struct SchemaView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                nodeSection
                edgeSection
                footer
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Schema").font(.title.bold())
            Text("InfiniteBrain follows the Infinite Brain architecture: every note is one of 16 node types, every link is one of 10 semantic edges. The classifier picks the type; `infer-edges` picks the edge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Node types · 16").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(NodeType.allCases, id: \.self) { type in
                    nodeCard(type)
                }
            }
        }
    }

    private func nodeCard(_ type: NodeType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Self.color(for: type)).frame(width: 12, height: 12)
                Text(type.rawValue).font(.system(.headline, design: .rounded))
                    .textCase(.lowercase)
                Spacer()
            }
            Text(type.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("e.g. \(type.example)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.4)))
    }

    private var edgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edge types · 10").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(EdgeType.allCases, id: \.self) { edge in
                    edgeCard(edge)
                }
            }
        }
    }

    private func edgeCard(_ edge: EdgeType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(edge.rawValue)
                .font(.system(.subheadline, design: .monospaced))
            Text(edge.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.4)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How to inspect", systemImage: "wand.and.stars")
                .font(.headline)
            Text("• Open the **Vault** tab and toggle **Raw .md** on any note. The frontmatter shows `type: <one-of-16>` and `edges: …` listing edge types.")
            Text("• Open the **Graph** tab. The sidebar legend uses the same 16 colours; clicking a node highlights its edges.")
            Text("• Edit the prompts that drive classification in `<vault>/.infinitebrain/skills/classify-node/SKILL.md` and `infer-edges/SKILL.md` — changes take effect on the next ingest.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// Mirrors the palette used by GraphView so the Schema and Graph views
    /// agree on what each type looks like.
    static func color(for type: NodeType) -> Color {
        switch type {
        case .pillar:    return Color(red: 0.30, green: 0.55, blue: 0.85)
        case .decision:  return Color(red: 0.85, green: 0.40, blue: 0.30)
        case .concept:   return Color(red: 0.50, green: 0.35, blue: 0.80)
        case .question:  return Color(red: 0.95, green: 0.65, blue: 0.20)
        case .playbook:  return Color(red: 0.20, green: 0.70, blue: 0.55)
        case .task:      return Color(red: 0.85, green: 0.55, blue: 0.85)
        case .event:     return Color(red: 0.55, green: 0.75, blue: 0.30)
        case .pattern:   return Color(red: 0.70, green: 0.45, blue: 0.20)
        case .hypothesis:return Color(red: 0.30, green: 0.65, blue: 0.85)
        case .fact:      return Color(red: 0.25, green: 0.65, blue: 0.35)
        case .source:    return Color(red: 0.45, green: 0.45, blue: 0.55)
        case .bookmark:  return Color(red: 0.95, green: 0.45, blue: 0.55)
        case .note:      return Color(red: 0.60, green: 0.60, blue: 0.60)
        case .contact:   return Color(red: 0.90, green: 0.75, blue: 0.40)
        case .reference: return Color(red: 0.40, green: 0.40, blue: 0.70)
        case .custom:    return Color(red: 0.80, green: 0.30, blue: 0.55)
        }
    }
}
