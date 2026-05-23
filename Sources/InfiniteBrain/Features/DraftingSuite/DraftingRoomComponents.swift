import SwiftUI
import InfiniteBrainCore

// MARK: - Outline Sidebar Component
struct OutlineSidebar: View {
    @ObservedObject var vm: DraftingViewModel
    let session: DraftingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OUTLINE").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Button { vm.addSection() } label: { Image(systemName: "plus.circle.fill").foregroundStyle(AppPalette.brand) }
                .buttonStyle(.plain)
            }
            .padding(20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.sections) { section in
                        SectionRow(
                            section: section,
                            isSelected: vm.selectedSectionId == section.id,
                            isDrafted: !section.content.isEmpty,
                            onDelete: { vm.removeSection(section.id) }
                        ) {
                            vm.selectedSectionId = section.id
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            
            HStack {
                Button("Discard") { vm.session = nil }.buttonStyle(.plain).font(.caption).foregroundStyle(AppPalette.error)
                Spacer()
                if vm.isWorking { ProgressView().controlSize(.small) }
            }
            .padding(20).background(Divider(), alignment: .top)
        }
        .frame(width: 280).background(AppPalette.sidebarBackground)
    }
}

// MARK: - Evidence Context Component
struct EvidenceContextView: View {
    let section: DraftSection
    let onToggle: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Evidence Context", systemImage: "quote.opening").font(.headline)
                Spacer()
                BadgeView("\(section.selectedCitationIds.count) sources", icon: "pin.fill")
            }
            if !section.selectedCitationIds.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(section.selectedCitationIds, id: \.self) { id in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                            Text(id).lineLimit(1)
                            Button { onToggle(id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppPalette.brand.opacity(0.1), in: Capsule()).foregroundStyle(AppPalette.brand)
                    }
                }
            } else {
                Text("Auto-retrieving resources based on topic...").font(.caption).italic().foregroundStyle(AppPalette.tertiary)
            }
        }
        .padding(20).background(AppPalette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 15))
    }
}

// MARK: - Section View Component
struct SectionRow: View {
    let section: DraftSection
    let isSelected: Bool
    let isDrafted: Bool
    let onDelete: () -> Void
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            Button(action: action) {
                HStack {
                    Circle().fill(isDrafted ? AppPalette.success : AppPalette.tertiary).frame(width: 8, height: 8)
                    Text(section.title).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(isSelected ? AppPalette.brand.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            if isHovering {
                Button(action: onDelete) { Image(systemName: "trash").font(.caption2).foregroundStyle(AppPalette.error.opacity(0.7)) }
                .buttonStyle(.plain).padding(.trailing, 8)
            }
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Main Editor Component
struct DraftEditor: View {
    @ObservedObject var vm: DraftingViewModel
    let session: DraftingSession
    let settings: AppSettings
    @State private var isPreviewMode = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let section = vm.selectedSection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // 1. Interactive Header
                        TextField("Title", text: Binding(
                            get: { section.title },
                            set: { var updated = session; if let idx = updated.sections.firstIndex(where: {$0.id == section.id}) { updated.sections[idx].title = $0; vm.session = updated } }
                        ))
                        .font(.system(size: 40, weight: .bold, design: .serif))
                        .textFieldStyle(.plain)

                        // 2. Evidence Context Window
                        EvidenceContextView(section: section) { id in
                            vm.toggleCitation(sectionId: section.id, noteId: id)
                        }
                        
                        // 3. AI Drafting Controller
                        AIDraftingPanel(vm: vm, section: section, settings: settings)
                        
                        // 4. Professional Document Surface
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Document Editor", systemImage: "pencil.and.outline").font(.headline)
                                Spacer()
                                // Toolbelt
                                HStack(spacing: 12) {
                                    wordCountPill(section.content)
                                    
                                    Picker("", selection: $isPreviewMode) {
                                        Text("Edit").tag(false)
                                        Text("Preview").tag(true)
                                    }
                                    .pickerStyle(.segmented).frame(width: 140)
                                }
                            }
                            
                            if isPreviewMode {
                                MarkdownPreview(markdown: section.content.formattingCitations())
                                    .padding(32)
                                    .frame(maxWidth: .infinity, minHeight: 800, alignment: .topLeading)
                                    .background(AppPalette.textBackground, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.border, lineWidth: 1))
                            } else {
                                TextEditor(text: Binding(
                                    get: { section.content },
                                    set: { vm.updateSectionContent(section.id, content: $0) }
                                ))
                                .font(.system(.body, design: .serif)).padding(32).frame(minHeight: 800)
                                .background(AppPalette.textBackground, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.border.opacity(0.5), lineWidth: 1))
                            }
                        }
                    }
                    .padding(60)
                }
                .overlay(alignment: .topTrailing) {
                    HStack {
                        SidebarToggle(isCollapsed: $vm.isOutlineCollapsed, direction: .leading)
                        SidebarToggle(isCollapsed: $vm.isReferencesCollapsed, direction: .trailing)
                    }
                    .padding(20)
                }
            } else {
                PlaceholderOutline(text: "Select a section from the outline to begin drafting.", icon: "doc.text.magnifyingglass")
                    .padding(100)
            }
        }
        .background(AppPalette.textBackground)
    }
    
    private func wordCountPill(_ content: String) -> some View {
        let count = content.split { $0.isWhitespace }.count
        return BadgeView("\(count) words", icon: "text.alignleft", color: .secondary)
    }
}

// MARK: - AI Drafting Controller
struct AIDraftingPanel: View {
    @ObservedObject var vm: DraftingViewModel
    let section: DraftSection
    let settings: AppSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Drafting Instructions").font(.headline)
                Spacer()
                if vm.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("AI Synthesis in progress...").font(.caption).foregroundStyle(AppPalette.brand)
                    }
                }
            }
            
            TextEditor(text: Binding(
                get: { section.customPrompt ?? "" },
                set: { vm.updateSectionInstruction(section.id, instruction: $0) }
            ))
            .font(.system(.subheadline, design: .monospaced))
            .frame(minHeight: 120).padding(12).background(AppPalette.textBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border, lineWidth: 1))
            .placeholder(when: (section.customPrompt ?? "").isEmpty) {
                Text("Describe what should be in this section (e.g. 'Compare the methodology of the source papers and highlight gaps')...")
                    .font(.subheadline).foregroundStyle(.tertiary).padding(.leading, 16).padding(.top, 20)
            }
            
            Button { Task { await vm.generateActiveSection(settings: settings) } } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(vm.isWorking ? "Synchronizing Context..." : "Generate Research Content")
                }
                .font(.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(vm.isWorking ? AppPalette.tertiary.opacity(0.3) : AppPalette.brand, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain).disabled(vm.isWorking)
        }
        .padding(24).background(AppPalette.surface.opacity(0.3), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppPalette.border, lineWidth: 1))
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .topLeading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

extension String {
    /// Sweeps the generated text for raw [[ID]] citation tokens and transforms them
    /// into elegant, hoverable HTML superscript badges for the rendered Markdown Preview.
    func formattingCitations() -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([a-zA-Z0-9_-]+)\\]\\]", options: []) else { return self }
        let nsString = self as NSString
        let results = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        
        var uniqueIds: [String] = []
        for result in results {
            if result.numberOfRanges > 1 {
                let id = nsString.substring(with: result.range(at: 1))
                if !uniqueIds.contains(id) { uniqueIds.append(id) }
            }
        }
        
        var output = self
        for (index, id) in uniqueIds.enumerated() {
            let html = "<sup style=\"display: inline-flex; align-items: center; justify-content: center; background-color: rgba(88,86,214,0.15); color: #5856D6; padding: 2px 6px; border-radius: 6px; font-size: 0.85em; font-weight: 700; font-family: -apple-system, BlinkMacSystemFont, sans-serif; cursor: help; line-height: 1; margin: 0 2px; text-decoration: none; border: 1px solid rgba(88,86,214,0.3);\" title=\"\(id)\">[\(index + 1)]</sup>"
            output = output.replacingOccurrences(of: "[[\(id)]]", with: html)
        }
        return output
    }
}
