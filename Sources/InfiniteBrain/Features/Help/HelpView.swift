import SwiftUI
import InfiniteBrainCore

/// Standalone Help window. Opened from the Help menu (Cmd-?) and from
/// Settings. Single source of truth for "how this app works": getting
/// started, the architecture, the pipeline, where to tune it,
/// troubleshooting, and the canonical reference for the 16 node types
/// and 10 edge types.
struct HelpView: View {
    @State private var selection: Topic = .gettingStarted

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            ScrollView {
                detail
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 760, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section { headerRow } header: { EmptyView() }
                .listRowSeparator(.hidden)

            Section("Basics") {
                row(.gettingStarted)
                row(.pipeline)
                row(.howIngestWorks)
            }
            Section("Architecture") {
                row(.nodeTypes)
                row(.edgeTypes)
                row(.vaultLayout)
            }
            Section("How-to") {
                row(.tuning)
                row(.resuming)
                row(.providers)
                row(.querying)
            }
            Section("Reference") {
                row(.troubleshooting)
                row(.shortcuts)
                row(.about)
            }
        }
        .listStyle(.sidebar)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("InfiniteBrain Help").font(.headline)
                Text("v\(Self.version)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func row(_ t: Topic) -> some View {
        Label(t.title, systemImage: t.icon).tag(t)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .gettingStarted:   gettingStartedSection
        case .pipeline:         pipelineSection
        case .howIngestWorks:   howIngestSection
        case .nodeTypes:        nodeTypesSection
        case .edgeTypes:        edgeTypesSection
        case .vaultLayout:      vaultLayoutSection
        case .tuning:           tuningSection
        case .resuming:         resumingSection
        case .providers:        providersSection
        case .querying:         queryingSection
        case .troubleshooting:  troubleshootingSection
        case .shortcuts:        shortcutsSection
        case .about:            aboutSection
        }
    }

    // MARK: - Sections

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Getting Started")
            para("InfiniteBrain turns documents into an AI-readable knowledge graph. Each PDF, markdown file, or text file becomes one Source note plus a fan-out of atomic notes — one per idea — labelled with a type and linked to related notes by semantic edges.")
            stepList([
                "Open Settings and pick a vault folder. An empty folder will be initialised; an existing Obsidian vault will be adopted.",
                "Choose an LLM provider. Anthropic API needs a key (saved to Keychain). Claude Code CLI / Codex / Cursor use the locally installed binary.",
                "Switch to the Ingest tab and drop a PDF or .md file in.",
                "Click Run. The activity log streams progress per chunk.",
                "When chunks finish, atomic notes appear in the Vault tab — drill in by type or use the filter.",
                "Use Query to ask the brain a question; the answer cites the notes it relied on."
            ])
            tip("First run also copies the AI prompts (\"skills\") into <vault>/.infinitebrain/skills/. Edit any SKILL.md to tune behaviour without rebuilding.")
        }
    }

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("The Pipeline")
            para("Each ingested file flows through six skills in order. All of them are markdown prompts you can edit.")
            codeBlock("""
            extract-pdf?    →   atomize-text   →   for each unit:
                                                    classify-node
                                                    summarize-note
                                                    reconcile-note   → skip / improve / add
                                                    infer-edges  ← only on add
                                                    write to vault
            """)
            para("Multiple chunks run in parallel up to the configured `concurrency`. Per-chunk completion is recorded in a checkpoint, so a Stop or crash leaves resumable state.")
        }
    }

    private var howIngestSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("How Ingest Works")
            bulletList([
                "Read the file. PDFs go through PDFKit (with Vision OCR fallback for scanned pages). EPUBs are unzipped and the spine's XHTML chapters are stripped to plain text. Markdown and .txt are read verbatim.",
                "Compute a SHA-256 of the content. Used as the dedup key.",
                "Write the Source note. Inherits the file name as folder name under notes/.",
                "Split text into chunks (default 16k chars). Per-chunk parallel pipeline begins.",
                "atomize-text converts a chunk into 50-300-line atomic units, skipping boilerplate (TOC, index, etc.).",
                "Each unit is classified into one of 16 node types, summarised in one sentence, and reconciled against the embedding index.",
                "Reconcile decides: skip duplicate, improve weaker existing note, or add fresh. infer-edges runs on add.",
                "Notes land in <vault>/notes/<source-slug>/<type>/<id>--<slug>.md."
            ])
        }
    }

    private var nodeTypesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("16 Node Types")
            para("The classifier picks exactly one type per atomic unit. Confidence below 0.7 reroutes to `custom` and flags the note for review.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                ForEach(NodeType.allCases, id: \.self) { t in
                    nodeCard(t)
                }
            }
        }
    }

    private func nodeCard(_ t: NodeType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(SchemaView.color(for: t)).frame(width: 10, height: 10)
                Text(t.rawValue).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            Text(t.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("e.g. \(t.example)").font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var edgeTypesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("10 Edge Types")
            para("infer-edges picks at most 8 edges per new note from a candidate list of nearest neighbours. Every edge requires a one-sentence evidence string grounded in the note body.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                ForEach(EdgeType.allCases, id: \.self) { e in
                    edgeCard(e)
                }
            }
        }
    }

    private func edgeCard(_ e: EdgeType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(e.rawValue).font(.system(.subheadline, design: .monospaced))
            Text(e.summary).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var vaultLayoutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Vault Layout")
            para("Each ingested file gets its own folder under notes/, organised by type. Source notes own their folder name; atomic notes inherit it.")
            codeBlock("""
            <vault>/
            ├── inbox/                              dropped files staged here
            ├── notes/
            │   └── <source-slug>/
            │       ├── source/<id>--<slug>.md
            │       ├── decision/<id>--<slug>.md
            │       ├── fact/<id>--<slug>.md
            │       └── concept/<id>--<slug>.md
            └── .infinitebrain/
                ├── embeddings.json                 vector index, rebuildable
                ├── checkpoints/sha256-<hash>.json  per-file resume state
                ├── skills/<name>/SKILL.md          editable per-vault prompts
                └── rules/*.mdc                     cross-cutting policies
            """)
        }
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Tuning the AI")
            para("Every skill is a markdown file. The bundled copies are in the app, but the first ingest copies them into <vault>/.infinitebrain/skills/ so you can edit per-vault without rebuilding.")
            bulletList([
                "atomize-text — split a chunk into atomic units; the content-selection rules live here",
                "classify-node — pick one of 16 types with confidence",
                "summarize-note — one-sentence ≤50-token summary",
                "reconcile-note — skip / improve / add decision",
                "improve-note — rewrite an existing note in place",
                "infer-edges — pick semantic edges with evidence",
                "answer-question — final answer with [[id]] citations",
                "select-notes-for-question — pass-1 retrieval (two-pass query)"
            ])
            para("Cross-cutting rules live in <vault>/.infinitebrain/rules/*.mdc — they're injected into every skill prompt. Citation policy, token budget, quality bar.")
            tip("Edits take effect on the next ingest. No restart, no rebuild.")
        }
    }

    private var resumingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Resume & Re-ingest")
            para("Long ingests are checkpointed per-chunk. If you click Stop, force-quit, or hit a crash, the partial work stays in the vault and a checkpoint records which chunks completed.")
            bulletList([
                "Drop the same file in and click Run — the orchestrator detects the checkpoint and skips the already-done chunks.",
                "Activity log will say `resuming previous ingest — N of M chunks still to do`.",
                "If the file content has changed, hash differs → fresh ingest.",
                "To force fresh on identical content, click Re-ingest. Confirms, deletes the source + every note citing it + the checkpoint, then runs from scratch.",
                "CLI parity: `infb ingest book.pdf --force` does the same wipe.",
                "Tip: re-ingest after editing skill prompts so notes reflect the new rules."
            ])
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("LLM Providers")
            para("Pick a backend in Settings. The system uses the same skill prompts; only the transport changes.")
            bulletList([
                "Anthropic API — direct HTTP. Requires an API key (Keychain). Fastest, most reliable.",
                "Claude Code CLI — shells out to your locally installed `claude`. No API key needed.",
                "Codex CLI — shells out to `codex`. No API key needed.",
                "Cursor CLI — shells out to `cursor agent`. No API key needed."
            ])
            para("CLI providers are slower (per-call subprocess overhead) but free. The first-run default picks an installed CLI if one is on your PATH and there's no Anthropic key in Keychain.")
        }
    }

    private var queryingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Querying")
            para("Two-pass retrieval keeps tokens cheap.")
            bulletList([
                "Pass 1 — embed your question, fetch top-12 nearest summaries from the index, ask `select-notes-for-question` which 4 bodies to load.",
                "Pass 2 — load only those bodies and ask `answer-question` to write the answer with [[id]] citations.",
                "Single-pass mode is available via the API for callers who want it (loads top-K full bodies up front)."
            ])
            tip("Citations like [[01KR0E671P5FNJKVEHGGN0A0DE]] resolve to vault files. Click in Vault tab to navigate.")
        }
    }

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Troubleshooting")
            VStack(alignment: .leading, spacing: 12) {
                troubleRow("Ingest seems frozen",
                           "Activity log capped at 500 lines. Check the latest entry for current chunk number. Long PDFs at concurrency=2 with Claude CLI take 10-30 minutes for a 1.7 MB book; this is normal.")
                troubleRow("App quit but Vault has fewer notes than expected",
                           "Drop the same file in, click Run. The checkpoint resumes the missing chunks. Existing atomic notes are kept.")
                troubleRow("Anthropic returns 429 rate limit",
                           "AnthropicClient retries on 429 / 5xx with exponential backoff and honors Retry-After. Three attempts then surfaces the error per chunk; the rest of the book continues.")
                troubleRow("`claude` CLI exits with 'nonzeroExit(1, stderr: \"\")'",
                           "Local CLI rate limit / contention under high concurrency. Default concurrency is 2; lower if you keep seeing this. The chunk auto-retries once before being skipped.")
                troubleRow("Scanned PDF produces zero notes",
                           "PDFKit returns empty text. Vision OCR runs as a fallback automatically. Watch for `OCR'd N of M page(s)` in the activity log — it's slower than text extraction.")
                troubleRow("Vault tab is empty after ingest",
                           "Click Refresh in the toolbar. The browser walks notes/<source>/<type>/ recursively; legacy notes/<type>/ also work.")
                troubleRow("Index out of sync (Query returns nothing)",
                           "Run `infb reindex <vault>` to rebuild embeddings.json from the markdown on disk.")
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Keyboard Shortcuts")
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("⌘↩", "Run / Ask — start an ingest from the Ingest tab or submit a question from the Query tab.")
                shortcutRow("⌘?", "Open this Help window.")
                shortcutRow("⌘,", "Open Settings (system default).")
                shortcutRow("⌘W", "Close this window.")
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("About")
            para("InfiniteBrain v\(Self.version) — a macOS app that turns documents into an AI-optimised knowledge graph following the Infinite Brain architecture (16 node types, 10 semantic edges, atomic 50–300-line notes).")
            para("Source: github.com/dnsmalla/InfiniteBrain")
            para("Pipeline skills are markdown — open them in <vault>/.infinitebrain/skills/. The repo's Resources/ folder has the bundled defaults.")
            tip("Companion CLI ships alongside the .app: `infb ingest`, `infb query`, `infb reindex`, `infb seed`. See `infb help`.")
        }
    }

    // MARK: - Components

    private func heading(_ s: String) -> some View {
        Text(s).font(.title.bold()).padding(.bottom, 4)
    }
    private func para(_ s: String) -> some View {
        Text(.init(s))
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)
    }
    private func tip(_ s: String) -> some View {
        Label(s, systemImage: "lightbulb")
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { t in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(.tertiary)
                    Text(.init(t)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func stepList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, t in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(idx + 1).")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    Text(.init(t)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func codeBlock(_ s: String) -> some View {
        Text(s)
            .font(.system(.callout, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
    }
    private func troubleRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.bold())
            Text(.init(body)).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func shortcutRow(_ key: String, _ body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(key)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(width: 64, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            Text(.init(body)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    enum Topic: String, Hashable, CaseIterable {
        case gettingStarted, pipeline, howIngestWorks
        case nodeTypes, edgeTypes, vaultLayout
        case tuning, resuming, providers, querying
        case troubleshooting, shortcuts, about

        var title: String {
            switch self {
            case .gettingStarted:   return "Getting Started"
            case .pipeline:         return "The Pipeline"
            case .howIngestWorks:   return "How Ingest Works"
            case .nodeTypes:        return "16 Node Types"
            case .edgeTypes:        return "10 Edge Types"
            case .vaultLayout:      return "Vault Layout"
            case .tuning:           return "Tuning the AI"
            case .resuming:         return "Resume & Re-ingest"
            case .providers:        return "LLM Providers"
            case .querying:         return "Querying"
            case .troubleshooting:  return "Troubleshooting"
            case .shortcuts:        return "Keyboard Shortcuts"
            case .about:            return "About"
            }
        }
        var icon: String {
            switch self {
            case .gettingStarted:   return "play.circle"
            case .pipeline:         return "arrow.triangle.branch"
            case .howIngestWorks:   return "tray.and.arrow.down"
            case .nodeTypes:        return "circle.grid.3x3"
            case .edgeTypes:        return "link"
            case .vaultLayout:      return "folder"
            case .tuning:           return "slider.horizontal.3"
            case .resuming:         return "arrow.counterclockwise.circle"
            case .providers:        return "cpu"
            case .querying:         return "sparkles.rectangle.stack"
            case .troubleshooting:  return "exclamationmark.triangle"
            case .shortcuts:        return "keyboard"
            case .about:            return "info.circle"
            }
        }
    }
}
