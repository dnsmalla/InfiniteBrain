import Foundation
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
        guard let apiKey   = parsed.apiKey else { fail("missing --api-key (or set ANTHROPIC_API_KEY)") }
        let files = parsed.positional
        guard !files.isEmpty else { fail("specify at least one file to ingest") }

        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        try VaultInitializer().ensureSeeded(vault: vault)

        let skillsRoot = BundledResources.skillsRoot(for: vault)
        let runner = SkillRunner(client: AnthropicClient(apiKey: apiKey), skillsRoot: skillsRoot)
        let index = EmbeddingIndex(storeURL: vault.sidecar.appendingPathComponent("embeddings.json"))
        try? await index.load()
        let orch = Orchestrator(
            skillRunner: runner,
            embeddings: NLEmbeddingProvider(),
            index: index,
            chunkSize: parsed.chunkSize ?? 16_000
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
        guard let apiKey   = parsed.apiKey else { fail("missing --api-key (or set ANTHROPIC_API_KEY)") }
        let question = parsed.positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { fail("specify a question") }

        let vault = Vault(root: URL(fileURLWithPath: vaultPath))
        let skillsRoot = BundledResources.skillsRoot(for: vault)
        let runner = SkillRunner(client: AnthropicClient(apiKey: apiKey), skillsRoot: skillsRoot)
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
        var topK: Int?
        var chunkSize: Int?
        var positional: [String] = []
    }

    static func parseFlags(_ args: [String]) -> Parsed {
        var p = Parsed()
        p.vault  = ProcessInfo.processInfo.environment["INFINITEBRAIN_VAULT"]
        p.apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--vault":      i += 1; p.vault = i < args.count ? args[i] : nil
            case "--api-key":    i += 1; p.apiKey = i < args.count ? args[i] : nil
            case "--top-k":      i += 1; p.topK = i < args.count ? Int(args[i]) : nil
            case "--chunk-size": i += 1; p.chunkSize = i < args.count ? Int(args[i]) : nil
            default:             p.positional.append(a)
            }
            i += 1
        }
        return p
    }

    // MARK: - Help

    static func printUsage() {
        print("""
        InfiniteBrain CLI — \(version())

        usage:
          infb ingest <file…> --vault <path> [--api-key <key>] [--chunk-size N]
          infb query <question…> --vault <path> [--api-key <key>] [--top-k N]
          infb seed <vault-path>
          infb version

        env:
          INFINITEBRAIN_VAULT   default --vault
          ANTHROPIC_API_KEY     default --api-key

        examples:
          infb ingest book.pdf  --vault ~/MyBrain
          infb query "what did we decide about pricing?" --vault ~/MyBrain
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
