import SwiftUI
import InfiniteBrainCore

struct QueryView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var vm = QueryViewModel()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            askBar
            
            if let e = vm.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
            }
            
            answerCard
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knowledge Retrieval")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Multimodal RAG with semantic cross-referencing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var askBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppPalette.brand)
                .font(.title3)
            
            TextField("Ask the brain anything about your vault...", text: $vm.question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($fieldFocused)
                .onSubmit { Task { await vm.ask(settings: settings) } }
            
            Button {
                Task { await vm.ask(settings: settings) }
            } label: {
                if vm.isAsking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppPalette.brand)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(vm.isAsking || vm.question.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private var answerCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if vm.answer.isEmpty && !vm.isAsking && vm.error == nil {
                    placeholder
                } else if !vm.answer.isEmpty {
                    Text(.init(vm.answer))
                        .font(.system(.body, design: .serif))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    
                    if !vm.citedIds.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                            Text("Cited Sources")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(vm.citedIds, id: \.self) { id in
                                    let note = vm.citedNotes[id]
                                    TagChip(
                                        title: note?.title ?? id,
                                        color: NodePalette.color(for: note?.type ?? .concept),
                                        id: id
                                    )
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recommended Queries", systemImage: "lightbulb.fill")
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(AppPalette.brand)
            
            VStack(alignment: .leading, spacing: 8) {
                ExampleRow(text: "What are the core concepts of the AtCoder book?")
                ExampleRow(text: "Explain the difference between Dijkstra and Bellman-Ford.")
                ExampleRow(text: "Summarize the greedy algorithms chapter.")
            }
        }
    }
}

private struct ExampleRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct TagChip: View {
    let title: String
    let color: Color
    let id: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.bold)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.2)))
        .help(id)
    }
}
