import SwiftUI

struct QueryView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var vm = QueryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Query the brain")
                .font(.title2.bold())

            HStack {
                TextField("Ask a question…", text: $vm.question, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await vm.ask(settings: settings) } }
                Button("Ask") {
                    Task { await vm.ask(settings: settings) }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(vm.isAsking || vm.question.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if vm.isAsking {
                HStack { ProgressView().controlSize(.small); Text("Searching…").foregroundStyle(.secondary) }
            }
            if let e = vm.error {
                Text(e).foregroundStyle(.red).font(.callout)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !vm.answer.isEmpty {
                        Text(.init(vm.answer))   // markdown-ish rendering
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !vm.citedIds.isEmpty {
                        Divider()
                        Text("Cited notes")
                            .font(.caption.smallCaps())
                            .foregroundStyle(.secondary)
                        ForEach(vm.citedIds, id: \.self) { id in
                            Text(id)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
    }
}
