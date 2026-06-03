import Foundation
import GraphKit
import CryptoKit
import InfiniteBrainCore
import SharedLLMKit

@main
struct InfiniteBrainCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            printUsage()
            exit(2)
        }
        do {
            switch cmd {
            case "ingest":   try await runIngest(Array(args.dropFirst()))
            case "query":    try await runQuery(Array(args.dropFirst()))
            case "seed":     try runSeed(Array(args.dropFirst()))
            case "reindex":  try await runReindex(Array(args.dropFirst()))
            case "version":  print(version())
            case "help", "-h", "--help": printUsage()
            default:
                print("unknown command: \(cmd)\n", to: &stderr)
                printUsage()
                exit(2)
            }
        } catch {
            print("error: \(error.localizedDescription)", to: &stderr)
            exit(1)
        }
    }

    // MARK: - Subcommands

    static func runIngest(_ args: [String]) async throws {
        let parsed = parseFlags(args)
        guard let vaultPath = parsed.vault else { fail("missing --vault (or set INFINITEBRAIN_VAULT)") }
        let files = parsed.positional
        guard !files.isEmpty else { fail("specify at least one file to ingest") }

        let provider = parsed.provider ?? .anthropic
        let client = try makeClient(provider: provider, apiKey: parsed.apiKey)
        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        try VaultInitializer().ensureSeeded(vault: vault)
        FileHandle.standardError.write(Data("provider: \(provider.displayName)\n".utf8))

        if parsed.force {
            try await wipePreviousIngests(files: files, vault: vault)
        }

        let skillsRoot = BundledResources.skillsRoot(for: vault)
        let runner = SkillRunner(client: client, skillsRoot: skillsRoot)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("embeddings.json"))
        try? await index.load()
        let orch = Orchestrator(
            skillRunner: runner,
            checkpoints: CheckpointStore(vault: vault),
            embeddings: NLEmbeddingProvider(),
            index: index,
            chunkSize: parsed.chunkSize ?? 16_000,
            onProgress: { line in print("   · \(line)") }
        )

        var totals = IngestResult()
        for f in files {
            let url = URL(fileURLWithPath: f)
            print("→ \(url.lastPathComponent)")
            let r = try await orch.ingest(file: url, into: vault)
            print("   added: \(r.added)  improved: \(r.improved)  skipped: \(r.skipped)")
            totals.added += r.added
            totals.improved += r.improved
            totals.skipped += r.skipped
            totals.quarantined += r.quarantined
        }
        print("done. total — added \(totals.added), improved \(totals.improved), skipped \(totals.skipped)")
    }

    static func runQuery(_ args: [String]) async throws {
        let parsed = parseFlags(args)
        guard let vaultPath = parsed.vault else { fail("missing --vault (or set INFINITEBRAIN_VAULT)") }
        let question = parsed.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { fail("specify a question") }

        let provider = parsed.provider ?? .anthropic
        let client = try makeClient(provider: provider, apiKey: parsed.apiKey)
        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        let skillsRoot = BundledResources.skillsRoot(for: vault)
        let runner = SkillRunner(client: client, skillsRoot: skillsRoot)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("embeddings.json"))
        try? await index.load()
        let service = QueryService(
            skillRunner: runner,
            store: VaultStore(vault: vault),
            embeddings: NLEmbeddingProvider(),
            index: index
        )

        let answer = try await service.ask(question, topK: parsed.topK ?? 6)
        print(answer.text)
        if !answer.citedIds.isEmpty {
            print("\nCited:")
            for id in answer.citedIds { print("  \(id)") }
        }
    }

    static func runReindex(_ args: [String]) async throws {
        let parsed = parseFlags(args)
        guard let vaultPath = parsed.vault ?? parsed.positional.first else {
            fail("missing --vault (or set INFINITEBRAIN_VAULT)")
        }
        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        print("rebuilding embedding index from \(vault.notesRoot.path)…")
        let index = try await IndexRebuilder.rebuild(
            vault: vault,
            embeddings: NLEmbeddingProvider()
        )
        // Quick sanity probe — count entries via a generous nearest call.
        let allHits = await index.nearest(to: [Float](repeating: 0.001, count: 512), k: 100_000)
        print("indexed \(allHits.count) note(s) at \(vault.sidecar.appendingPathComponent("embeddings.json").path)")
    }

    static func runSeed(_ args: [String]) throws {
        let parsed = parseFlags(args)
        guard let vaultPath = parsed.vault ?? parsed.positional.first else {
            fail("missing vault path")
        }
        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        try VaultInitializer().ensureSeeded(vault: vault)
        print("seeded \(vault.root.path)")
    }

    // MARK: - Flag parsing

    struct Parsed {
        var vault: String?
        var apiKey: String?
        var provider: LLMProviderKind?
        var topK: Int?
        var chunkSize: Int?
        var force: Bool = false
        var positional: [String] = []
    }

    static func parseFlags(_ args: [String]) -> Parsed {
        var p = Parsed()
        p.vault  = ProcessInfo.processInfo.environment["INFINITEBRAIN_VAULT"]
        p.apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        if let raw = ProcessInfo.processInfo.environment["INFINITEBRAIN_PROVIDER"] {
            p.provider = LLMProviderKind(rawValue: raw)
        }

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--vault":      i += 1; p.vault = i < args.count ? args[i] : nil
            case "--api-key":    i += 1; p.apiKey = i < args.count ? args[i] : nil
            case "--provider":   i += 1; p.provider = i < args.count ? LLMProviderKind(rawValue: args[i]) : nil
            case "--top-k":      i += 1; p.topK = i < args.count ? Int(args[i]) : nil
            case "--chunk-size": i += 1; p.chunkSize = i < args.count ? Int(args[i]) : nil
            case "--force":      p.force = true
            default:             p.positional.append(a)
            }
            i += 1
        }
        return p
    }

    static func wipePreviousIngests(files: [String], vault: Vault) async throws {
        let store = VaultStore(vault: vault)
        let cps = CheckpointStore(vault: vault)
        for f in files {
            let url = URL(fileURLWithPath: f)
            guard let text = try? InputReader.read(url).text else { continue }
            let hash = "sha256-" + sha256Hex(text)
            let all = (try? await store.allNotes()) ?? []
            guard let prior = all.first(where: { $0.type == .source && $0.contentHash == hash }) else {
                continue
            }
            let toDelete = all.filter { $0.id == prior.id || $0.sources.contains(prior.id) }
            for n in toDelete { try? await store.delete(id: n.id) }
            try? await cps.delete(fileHash: hash)
            FileHandle.standardError.write(Data("wiped previous ingest of \(url.lastPathComponent): \(toDelete.count) note(s)\n".utf8))
        }
    }

    static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func makeClient(provider: LLMProviderKind, apiKey: String?) throws -> LLMClient {
        do {
            return try LLMClientFactory.make(provider: provider, apiKey: apiKey)
        } catch LLMClientFactory.FactoryError.missingAPIKey {
            fail("--provider anthropic needs --api-key (or ANTHROPIC_API_KEY)")
        } catch CLIClientError.executableNotFound(let name) {
            fail("`\(name)` CLI not found on PATH. Install it or use --provider anthropic.")
        }
    }

    // MARK: - Help

    static func printUsage() {
        print("""
        InfiniteBrain CLI — \(version())

        usage:
          infb ingest <file…> --vault <path> [--provider P] [--api-key K] [--chunk-size N] [--force]
          infb query <question…> --vault <path> [--provider P] [--api-key K] [--top-k N]
          infb seed <vault-path>
          infb reindex <vault-path>
          infb version

        --provider values: anthropic (default) | claude-cli | codex-cli | cursor-cli
          The CLI providers shell out to the locally installed `claude`,
          `codex`, or `cursor` binary — no API key needed.

        env:
          INFINITEBRAIN_VAULT     default --vault
          ANTHROPIC_API_KEY       default --api-key (anthropic provider only)
          INFINITEBRAIN_PROVIDER  default --provider

        examples:
          infb ingest book.pdf --vault ~/MyBrain
          infb ingest book.pdf --vault ~/MyBrain --provider claude-cli
          infb query "what did we decide about pricing?" --vault ~/MyBrain --provider codex-cli
        """)
    }

    static func version() -> String { "0.5.0" }

    static func fail(_ msg: String) -> Never {
        print("error: \(msg)", to: &stderr)
        exit(2)
    }
}

// stderr handle compatible with `print(..., to:)`
struct StderrStream: TextOutputStream {
    mutating func write(_ string: String) { FileHandle.standardError.write(Data(string.utf8)) }
}
nonisolated(unsafe) var stderr = StderrStream()
