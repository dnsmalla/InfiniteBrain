import SwiftUI
import InfiniteBrainCore

// MARK: - Main Setup View

struct DraftingSetupView: View {
    @ObservedObject var vm: DraftingViewModel
    @EnvironmentObject var settings: AppSettings
    @Binding var showingResumeView: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                DraftingRoomHeader()

                HStack(alignment: .top, spacing: 32) {
                    HistoryPanel(vm: vm, showingResumeView: $showingResumeView, settings: settings)
                    NewDocumentPanel(vm: vm, showingResumeView: $showingResumeView)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await vm.importFiles(urls: urls, settings: settings) }
            return true
        }
    }
}

// MARK: - Header

private struct DraftingRoomHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 64))
                .foregroundStyle(AppPalette.brand.gradient)
            Text("Drafting Room")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Interactive research synthesis and document generation.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }
}

// MARK: - History Panel

private struct HistoryPanel: View {
    @ObservedObject var vm: DraftingViewModel
    @Binding var showingResumeView: Bool
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("History & Drafts", systemImage: "clock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !vm.recentSessions.isEmpty {
                    BadgeView("\(vm.recentSessions.count)")
                }
            }

            if vm.recentSessions.isEmpty {
                PlaceholderOutline(text: "No recent drafts found.", icon: "clock.badge.questionmark")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(vm.recentSessions, id: \.topic) { session in
                            HistoryRow(session: session, settings: settings) {
                                vm.resumeSession(session)
                                showingResumeView = false
                            } onDelete: {
                                vm.deleteSession(session, settings: settings)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppPalette.border, lineWidth: 1))
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let session: DraftingSession
    let settings: AppSettings
    let action: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var draftedCount: Int { session.sections.filter { !$0.content.isEmpty }.count }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppPalette.brand.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppPalette.brand)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.topic)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(session.sections.count) sections · \(draftedCount) drafted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    BadgeView(session.template)
                    if isHovered {
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red.opacity(0.75))
                                .padding(5)
                                .background(Color.red.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? AppPalette.brand.opacity(0.06) : AppPalette.textBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? AppPalette.brand.opacity(0.25) : AppPalette.border.opacity(0.5), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .alert("Delete Draft?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove '\(session.topic)' and all its drafted content. This action cannot be undone.")
        }
    }
}

// MARK: - New Document Panel

private struct NewDocumentPanel: View {
    @ObservedObject var vm: DraftingViewModel
    @EnvironmentObject var settings: AppSettings
    @Binding var showingResumeView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Create New Document", systemImage: "plus.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 24) {
                SourceSelectionStep(vm: vm)
                Divider()
                ProjectDetailsStep(vm: vm, showingResumeView: $showingResumeView)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppPalette.border, lineWidth: 1))
        }
    }
}

// MARK: - Source Selection Step

private struct SourceSelectionStep: View {
    @ObservedObject var vm: DraftingViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step label
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(AppPalette.brand.opacity(0.12)).frame(width: 22, height: 22)
                    Text("1").font(.system(size: 11, weight: .bold)).foregroundStyle(AppPalette.brand)
                }
                Text("Select Base Sources").font(.headline)
            }

            // Search bar + Import button row
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.subheadline)
                    TextField("Search vault for notes...", text: $vm.noteSearchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: vm.noteSearchQuery) { _, _ in
                            Task { await vm.searchNotes(settings: settings) }
                        }
                    // + adds all current search results to citations
                    if !vm.searchResults.isEmpty {
                        Button {
                            vm.addSearchResultsToCitations()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppPalette.brand)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(AppPalette.textBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.border, lineWidth: 1))

                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = true
                    if panel.runModal() == .OK {
                        Task { await vm.importFiles(urls: panel.urls, settings: settings) }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "plus.rectangle.on.folder.fill").font(.subheadline)
                        Text("Import").font(.system(size: 10, weight: .bold))
                    }
                    .frame(height: 42)
                    .padding(.horizontal, 14)
                    .background(AppPalette.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.brand.opacity(0.2), lineWidth: 1))
                }.buttonStyle(.plain)
            }

            // Search results — tap to add individual notes
            if !vm.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap to add:").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(vm.searchResults, id: \.id) { note in
                        Button {
                            let label = note.title.isEmpty ? note.id : note.title
                            if !vm.globalSelectedCitations.contains(label) {
                                vm.globalSelectedCitations.append(label)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                                Text(note.title.isEmpty ? note.id : note.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "plus.circle").font(.caption).foregroundStyle(AppPalette.brand)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppPalette.brand.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }

            // Subtle background-indexing indicator (non-blocking)
            if let status = vm.ingestionStatus {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                    Text(status).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppPalette.brand.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(AppPalette.brand.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Selected sources — fixed-height scrollable so the panel never shifts
            if !vm.globalSelectedCitations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Selected Sources (\(vm.globalSelectedCitations.count))")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear all") { vm.globalSelectedCitations.removeAll() }
                            .font(.caption)
                            .foregroundStyle(AppPalette.error.opacity(0.8))
                            .buttonStyle(.plain)
                    }
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(vm.globalSelectedCitations, id: \.self) { id in
                                HStack {
                                    Image(systemName: "folder.fill").font(.caption).foregroundStyle(AppPalette.brand.opacity(0.7))
                                    Text(id).font(.caption).lineLimit(1)
                                    Spacer()
                                    Button { vm.toggleGlobalCitation(id) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(AppPalette.error.opacity(0.7))
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 130)   // fixed height — prevent layout shift
                }
                .padding(12)
                .background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border.opacity(0.5), lineWidth: 1))
            }
        }
    }
}

// MARK: - Project Details Step

private struct ProjectDetailsStep: View {
    @ObservedObject var vm: DraftingViewModel
    @EnvironmentObject var settings: AppSettings
    @Binding var showingResumeView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(AppPalette.brand.opacity(0.12)).frame(width: 22, height: 22)
                    Text("2").font(.system(size: 11, weight: .bold)).foregroundStyle(AppPalette.brand)
                }
                Text("Project Details").font(.headline)
            }

            TextField("Enter research topic...", text: $vm.newTopic)
                .textFieldStyle(.plain)
                .padding(12)
                .background(AppPalette.textBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.border, lineWidth: 1))

            Picker("", selection: $vm.newTemplate) {
                ForEach(vm.templates, id: \.self) { t in Text(t).tag(t) }
            }
            .pickerStyle(.segmented)

            Button {
                showingResumeView = false
                Task { await vm.startSession(settings: settings) }
            } label: {
                Text(vm.isWorking ? "Starting…" : "Start Drafting Pipeline")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        vm.canStart ? AppPalette.brand : AppPalette.tertiary,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!vm.canStart || vm.isWorking)
        }
    }
}
