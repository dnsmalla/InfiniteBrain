import SwiftUI
import InfiniteBrainCore

struct DraftingRoom: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var vm = DraftingViewModel()
    @State private var showingResumeView: Bool = false
    
    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // 1. Outline Sidebar
                if !vm.isOutlineCollapsed, let session = vm.session, !showingResumeView {
                    OutlineSidebar(vm: vm, session: session)
                    Divider()
                }
                
                // 2. Main Editor Area
                if let session = vm.session, !showingResumeView {
                    DraftEditor(vm: vm, session: session, settings: settings)
                } else {
                    DraftingSetupView(vm: vm, showingResumeView: $showingResumeView)
                }
                
                // 3. Reference Sidebar
                if !vm.isReferencesCollapsed, let session = vm.session, !showingResumeView {
                    Divider()
                    referenceSidebar(session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let e = vm.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(AppPalette.error, in: Capsule())
                        .padding(.top, 40)
                }
            }
            .toolbar {
                if vm.session != nil && !showingResumeView {
                    ToolbarItem(placement: .navigation) {
                        Button { showingResumeView = true } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Dashboard")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if vm.session != nil { showingResumeView = true }
            Task { await vm.loadRecentSessions(settings: settings) }
        }
        .onChange(of: vm.session) { _, _ in
            Task { await vm.saveSession(settings: settings) }
        }
        .onChange(of: showingResumeView) { _, isShowing in
            if isShowing {
                Task { await vm.loadRecentSessions(settings: settings) }
            }
        }
    }
    

    // MARK: - Reference Sidebar
    private func referenceSidebar(_ session: DraftingSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REFERENCES").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = true
                    if panel.runModal() == .OK { Task { await vm.importFiles(urls: panel.urls, settings: settings) } }
                } label: { Image(systemName: "plus.rectangle.on.folder.fill").foregroundStyle(AppPalette.brand) }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            VStack(spacing: 12) {
                if !session.globalCitationIds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Library").font(.caption.bold()).foregroundStyle(.secondary)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(session.globalCitationIds, id: \.self) { id in
                                    let isPinned = vm.selectedSection?.selectedCitationIds.contains(id) ?? false
                                    Button { vm.toggleCitation(sectionId: vm.selectedSectionId ?? "", noteId: id) } label: {
                                        HStack {
                                            Image(systemName: isPinned ? "pin.fill" : "pin").font(.caption)
                                            Text(id).font(.caption).lineLimit(1)
                                            Spacer()
                                            if isPinned { Image(systemName: "checkmark").font(.caption) }
                                        }
                                        .padding(8).background(isPinned ? AppPalette.brand.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(isPinned ? AppPalette.brand : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    .padding(.horizontal, 20)
                }
                Divider().padding(.horizontal, 20)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes...", text: $vm.noteSearchQuery).textFieldStyle(.plain)
                        .onSubmit { Task { await vm.searchNotes(settings: settings) } }
                }
                .padding(10).background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            }
            Spacer()
        }
        .frame(width: 260).background(AppPalette.sidebarBackground)
    }
}
