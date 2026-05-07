import SwiftUI
import InfiniteBrainCore

struct QueryView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var vm = QueryViewModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            askBar
            if let e = vm.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            answerCard
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ask the brain").font(.title.bold())
            Text("Two-pass retrieval: a cheap selector picks which notes' bodies to load, then a generator answers with citations.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var askBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Ask a question…", text: $vm.question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .onSubmit { Task { await vm.ask(settings: settings) } }
            Button {
                Task { await vm.ask(settings: settings) }
            } label: {
                if vm.isAsking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Ask", systemImage: "arrow.up.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(vm.isAsking || vm.question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private var answerCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if vm.answer.isEmpty && !vm.isAsking && vm.error == nil {
                    placeholder
                } else if !vm.answer.isEmpty {
                    Text(.init(vm.answer))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if !vm.citedIds.isEmpty {
                        Divider()
                        Text("Cited notes")
                            .font(.caption.smallCaps())
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(vm.citedIds, id: \.self) { id in
                                Text(id)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.background.secondary, in: Capsule())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Examples", systemImage: "lightbulb")
                .font(.callout.smallCaps())
                .foregroundStyle(.secondary)
            Text("• What did we decide about pricing for the Indie plan?")
                .foregroundStyle(.secondary)
            Text("• What facts contradict the original hypothesis about churn?")
                .foregroundStyle(.secondary)
            Text("• List every open question tagged with the launch pillar.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

/// Tiny flow layout for the citation chips so they wrap naturally.
private struct FlowLayout: Layout {
    let spacing: CGFloat
    init(spacing: CGFloat = 6) { self.spacing = spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var (rowW, rowH, totalH): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        var maxW: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if rowW + size.width > width {
                totalH += rowH + spacing
                maxW = max(maxW, rowW)
                rowW = 0; rowH = 0
            }
            rowW += size.width + spacing
            rowH = max(rowH, size.height)
        }
        totalH += rowH
        maxW = max(maxW, rowW)
        return CGSize(width: min(width, maxW), height: totalH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
