import SwiftUI
import InfiniteBrainCore

struct DraftingSetupView: View {
    @ObservedObject var vm: DraftingViewModel
    @EnvironmentObject var settings: AppSettings
    @Binding var showingResumeView: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                // Header
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
                
                // Dashboard
                VStack(spacing: 32) {
                    // HISTORY & RECENT DOCUMENTS
                    VStack(alignment: .leading, spacing: 16) {
                        Text("HISTORY & DRAFTS").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        
                        if vm.recentSessions.isEmpty {
                            PlaceholderOutline(text: "No recent drafts found in your vault.", icon: "clock.badge.questionmark")
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(vm.recentSessions, id: \.topic) { session in
                                        Button {
                                            vm.resumeSession(session)
                                            showingResumeView = false
                                        } label: {
                                            VStack(alignment: .leading, spacing: 12) {
                                                HStack {
                                                    Image(systemName: "doc.text.fill").foregroundStyle(AppPalette.brand)
                                                    Spacer()
                                                    BadgeView(session.template)
                                                }
                                                
                                                Text(session.topic).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                                
                                                Text("\(session.sections.count) sections • \(session.sections.filter({!$0.content.isEmpty}).count) drafted")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(width: 200, alignment: .leading)
                                            .cardStyle()
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: 600)

                    // CREATE NEW DOCUMENT
                    VStack(alignment: .leading, spacing: 24) {
                        Text("CREATE NEW DOCUMENT").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 28) {
                            // Step 1: SOURCE SELECTION
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Step 1: Select Base Sources").font(.headline)
                                
                                HStack(spacing: 12) {
                                    HStack {
                                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                        TextField("Search vault for files...", text: $vm.noteSearchQuery)
                                            .textFieldStyle(.plain)
                                            .onChange(of: vm.noteSearchQuery) { _ in
                                                Task { await vm.searchNotes(settings: settings) }
                                            }
                                        
                                        Button {
                                            Task { await vm.searchNotes(settings: settings) }
                                        } label: {
                                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(AppPalette.brand)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(12)
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
                                        VStack(spacing: 4) {
                                            Image(systemName: "plus.rectangle.on.folder.fill")
                                            Text("Import").font(.system(size: 10, weight: .bold))
                                        }
                                        .frame(height: 44)
                                        .padding(.horizontal, 16)
                                        .background(AppPalette.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.brand.opacity(0.2), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                if let status = vm.ingestionStatus {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text(status).font(.caption).foregroundStyle(AppPalette.brand)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppPalette.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                                }
                                
                                if !vm.searchResults.isEmpty || !vm.globalSelectedCitations.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        if !vm.globalSelectedCitations.isEmpty {
                                            Text("Selected (\(vm.globalSelectedCitations.count))").font(.caption.bold())
                                            ForEach(vm.globalSelectedCitations, id: \.self) { id in
                                                HStack {
                                                    Image(systemName: "doc.fill").font(.caption).foregroundStyle(.secondary)
                                                    Text(id).font(.caption).lineLimit(1)
                                                    Spacer()
                                                    Button { vm.toggleGlobalCitation(id) } label: {
                                                        Image(systemName: "minus.circle.fill").foregroundStyle(AppPalette.error.opacity(0.7))
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                                .padding(6).background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                                            }
                                        }
                                    }
                                    .padding(12).background(Color.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            
                            Divider()
                            
                            // Step 2: PROJECT IDENTITY
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Step 2: Project Details").font(.headline)
                                TextField("Enter topic...", text: $vm.newTopic)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(AppPalette.textBackground, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.border, lineWidth: 1))
                                
                                Picker("", selection: $vm.newTemplate) {
                                    ForEach(vm.templates, id: \.self) { t in Text(t).tag(t) }
                                }
                                .pickerStyle(.segmented)
                            }
                            
                            Button {
                                showingResumeView = false
                                Task { await vm.startSession(settings: settings) }
                            } label: {
                                Text("Start Drafting Pipeline")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(vm.canStart ? AppPalette.brand : AppPalette.tertiary, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(!vm.canStart || vm.isWorking)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppPalette.border, lineWidth: 1))
                    }
                    .frame(maxWidth: 600)
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
