# Codebase Index

| Field | Value |
|-------|-------|
| **Files** | 139 |
| **Languages** | javascript, python, swift |
| **Total lines** | 12730 |

## High-Impact Files
> Files most depended on — change these with care.

| File | Role | Used By | Functions |
|------|------|---------|-----------|

## Files by Role

### Client (2 files)

- `SharedLLMKit/Sources/SharedLLMKit/Client/AnthropicClient.swift` — 116 lines, 4 functions
- `SharedLLMKit/Sources/SharedLLMKit/Client/LLMClient.swift` — 25 lines, 2 functions

### CodeGraph (15 files)

- `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphCanvas.swift` — 361 lines, 16 functions
- `Sources/InfiniteBrain/Features/CodeGraph/UAHelpers.swift` — 94 lines, 6 functions
- `Sources/InfiniteBrainCore/CodeGraph/CGSimulation.swift` — 128 lines, 4 functions
- `Sources/InfiniteBrainCore/CodeGraph/CodeGraphLayout.swift` — 37 lines, 1 functions
- `Sources/InfiniteBrainCore/CodeGraph/CodeGraphModels.swift` — 150 lines, 1 functions
- `Sources/InfiniteBrainCore/CodeGraph/CodeNoteWriter.swift` — 255 lines, 6 functions
- `Sources/InfiniteBrainCore/CodeGraph/FileStructureExtractor.swift` — 182 lines, 11 functions
- `Sources/InfiniteBrainCore/CodeGraph/ImportResolver.swift` — 46 lines, 4 functions
- `Sources/InfiniteBrainCore/CodeGraph/ProcessLauncher.swift` — 65 lines, 2 functions
- `Sources/InfiniteBrainCore/CodeGraph/PythonASTExtractor.swift` — 54 lines, 4 functions
- `Sources/InfiniteBrainCore/CodeGraph/RawFileStructure.swift` — 20 lines, 0 functions
- `Sources/InfiniteBrainCore/CodeGraph/ScanResult.swift` — 28 lines, 0 functions
- `Sources/InfiniteBrainCore/CodeGraph/StructureGraphBuilder.swift` — 57 lines, 1 functions
- `Sources/InfiniteBrainCore/CodeGraph/StructureScanner.swift` — 42 lines, 2 functions
- `Sources/InfiniteBrainCore/CodeGraph/UAParser.swift` — 173 lines, 4 functions

### Error (1 files)

- `Sources/InfiniteBrainCore/CodeGraph/UAError.swift` — 11 lines, 0 functions

### Infrastructure (5 files)

- `Sources/InfiniteBrainCore/Infrastructure/AppSettings.swift` — 79 lines, 4 functions
- `Sources/InfiniteBrainCore/Infrastructure/GlobalRateGate.swift` — 49 lines, 5 functions
- `Sources/InfiniteBrainCore/Infrastructure/IDGenerator.swift` — 31 lines, 4 functions
- `Sources/InfiniteBrainCore/Infrastructure/LocalMLProvider.swift` — 17 lines, 1 functions
- `Sources/InfiniteBrainCore/Infrastructure/UsageTracker.swift` — 58 lines, 5 functions

### Model (6 files)

- `Sources/InfiniteBrainCore/Models/EdgeType.swift` — 24 lines, 0 functions
- `Sources/InfiniteBrainCore/Models/NodeType+Schema.swift` — 68 lines, 0 functions
- `Sources/InfiniteBrainCore/Models/NodeType.swift` — 38 lines, 0 functions
- `Sources/InfiniteBrainCore/Models/Note.swift` — 46 lines, 0 functions
- `Sources/InfiniteBrainCore/Models/QuadTree.swift` — 54 lines, 4 functions
- `Sources/InfiniteBrainCore/Models/Vault.swift` — 12 lines, 0 functions

### Module (33 files)

- `Package.swift` — 49 lines, 0 functions
- `SharedLLMKit/Package.swift` — 22 lines, 0 functions
- `SharedLLMKit/Sources/SharedLLMKit/Client/CLIClients.swift` — 122 lines, 7 functions
- `SharedLLMKit/Sources/SharedLLMKit/Client/CLIProcessRunner.swift` — 99 lines, 4 functions
- `SharedLLMKit/Sources/SharedLLMKit/Client/LLMGate.swift` — 11 lines, 2 functions
- `SharedLLMKit/Sources/SharedLLMKit/Client/LLMProvider.swift` — 51 lines, 2 functions
- `SharedLLMKit/Sources/SharedLLMKit/Embeddings/EmbeddingIndex.swift` — 131 lines, 8 functions
- `SharedLLMKit/Sources/SharedLLMKit/Embeddings/EmbeddingProvider.swift` — 4 lines, 1 functions
- `SharedLLMKit/Sources/SharedLLMKit/Embeddings/NLEmbeddingProvider.swift` — 32 lines, 1 functions
- `SharedLLMKit/Sources/SharedLLMKit/Schema/SchemaValidator.swift` — 46 lines, 2 functions
- `SharedLLMKit/Sources/SharedLLMKit/SharedLLMKit.swift` — 6 lines, 0 functions
- `SharedLLMKit/Sources/SharedLLMKit/SkillRunner/Skill.swift` — 137 lines, 5 functions
- `SharedLLMKit/Sources/SharedLLMKit/SkillRunner/SkillRunner.swift` — 151 lines, 8 functions
- `Sources/InfiniteBrain/App/InfiniteBrainApp.swift` — 247 lines, 0 functions
- `Sources/InfiniteBrain/CoreUI/AppPalette.swift` — 48 lines, 2 functions
- `Sources/InfiniteBrain/CoreUI/GraphCanvas.swift` — 123 lines, 1 functions
- `Sources/InfiniteBrain/CoreUI/UIComponents.swift` — 97 lines, 2 functions
- `Sources/InfiniteBrain/Features/DraftingSuite/DraftingRoom.swift` — 118 lines, 1 functions
- `Sources/InfiniteBrain/Features/DraftingSuite/DraftingRoomComponents.swift` — 254 lines, 3 functions
- `Sources/InfiniteBrain/Features/KnowledgeGraph/NodePalette.swift` — 25 lines, 1 functions
- `Sources/InfiniteBrain/Features/VaultBrowser/VaultBrowser.swift` — 260 lines, 6 functions
- `Sources/InfiniteBrainCLI/main.swift` — 215 lines, 13 functions
- `Sources/InfiniteBrainCore/BundledResources.swift` — 25 lines, 1 functions
- `Sources/InfiniteBrainCore/Extraction/DocumentScanner.swift` — 48 lines, 1 functions
- `Sources/InfiniteBrainCore/Extraction/EPUBExtractor.swift` — 154 lines, 5 functions
- `Sources/InfiniteBrainCore/Extraction/InputReader.swift` — 30 lines, 1 functions
- `Sources/InfiniteBrainCore/Extraction/PDFExtractor.swift` — 85 lines, 3 functions
- `Sources/InfiniteBrainCore/Extraction/TextChunker.swift` — 107 lines, 2 functions
- `Sources/InfiniteBrainCore/Graph/GraphLayout.swift` — 90 lines, 1 functions
- `Sources/InfiniteBrainCore/Graph/GraphSimulation.swift` — 115 lines, 4 functions
- `Sources/InfiniteBrainCore/Resources/code_ast_scan.py` — 57 lines, 2 functions
- `scratch.swift` — 10 lines, 0 functions
- `scratch/scratch.swift` — 36 lines, 0 functions

### Persistence (7 files)

- `Sources/InfiniteBrainCore/Persistence/BacklinkIndex.swift` — 40 lines, 5 functions
- `Sources/InfiniteBrainCore/Persistence/IndexRebuilder.swift` — 35 lines, 1 functions
- `Sources/InfiniteBrainCore/Persistence/Keychain.swift` — 48 lines, 4 functions
- `Sources/InfiniteBrainCore/Persistence/MetadataIndex.swift` — 149 lines, 13 functions
- `Sources/InfiniteBrainCore/Persistence/NoteSerializer.swift` — 184 lines, 7 functions
- `Sources/InfiniteBrainCore/Persistence/VaultInitializer.swift` — 38 lines, 2 functions
- `Sources/InfiniteBrainCore/Persistence/VaultWatcher.swift` — 44 lines, 1 functions

### Service (7 files)

- `Sources/InfiniteBrainCore/Infrastructure/LogService.swift` — 48 lines, 5 functions
- `Sources/InfiniteBrainCore/Services/DraftingService.swift` — 149 lines, 5 functions
- `Sources/InfiniteBrainCore/Services/Orchestrator.swift` — 478 lines, 10 functions
- `Sources/InfiniteBrainCore/Services/QueryService.swift` — 194 lines, 4 functions
- `Sources/InfiniteBrainCore/Services/SkillSyncService.swift` — 35 lines, 1 functions
- `Sources/InfiniteBrainCore/Services/UnifiedIngestionService.swift` — 47 lines, 3 functions
- `Sources/InfiniteBrainCore/Services/VaultHealthService.swift` — 90 lines, 2 functions

### Store (3 files)

- `Sources/InfiniteBrainCore/CodeGraph/UAStore.swift` — 66 lines, 6 functions
- `Sources/InfiniteBrainCore/Persistence/CheckpointStore.swift` — 58 lines, 5 functions
- `Sources/InfiniteBrainCore/Persistence/VaultStore.swift` — 171 lines, 13 functions

### Test (45 files)

- `SharedLLMKit/Tests/SharedLLMKitTests/AnthropicClientTests.swift` — 100 lines, 9 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/AnthropicRetryTests.swift` — 55 lines, 5 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/BundledSkillsTests.swift` — 36 lines, 1 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/CLIClientArgumentTests.swift` — 31 lines, 5 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/EmbeddingIndexTests.swift` — 54 lines, 5 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/SchemaValidatorTests.swift` — 46 lines, 4 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/SharedLLMKitTests.swift` — 7 lines, 1 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/SkillParseTests.swift` — 50 lines, 3 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/SkillRunnerBudgetTests.swift` — 73 lines, 5 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/SkillRunnerHedgingTests.swift` — 94 lines, 6 functions
- `SharedLLMKit/Tests/SharedLLMKitTests/SkillRunnerTests.swift` — 104 lines, 6 functions
- `Tests/InfiniteBrainTests/AppSettingsTests.swift` — 53 lines, 6 functions
- `Tests/InfiniteBrainTests/CGSimulationTests.swift` — 50 lines, 4 functions
- `Tests/InfiniteBrainTests/CheckpointStoreTests.swift` — 43 lines, 3 functions
- `Tests/InfiniteBrainTests/CodeGraphLayoutTests.swift` — 42 lines, 4 functions
- `Tests/InfiniteBrainTests/ConcurrencyTests.swift` — 54 lines, 1 functions
- `Tests/InfiniteBrainTests/DuplicateIngestTests.swift` — 40 lines, 2 functions
- `Tests/InfiniteBrainTests/EPUBExtractorTests.swift` — 108 lines, 5 functions
- `Tests/InfiniteBrainTests/EdgeInferenceTests.swift` — 52 lines, 1 functions
- `Tests/InfiniteBrainTests/EdgeTypeTests.swift` — 21 lines, 3 functions
- `Tests/InfiniteBrainTests/GraphLayoutTests.swift` — 49 lines, 3 functions
- `Tests/InfiniteBrainTests/GraphNodeMetadataTests.swift` — 16 lines, 2 functions
- `Tests/InfiniteBrainTests/GraphifyParserTests.swift` — 84 lines, 8 functions
- `Tests/InfiniteBrainTests/GraphifyStoreTests.swift` — 47 lines, 7 functions
- `Tests/InfiniteBrainTests/ImportResolverTests.swift` — 50 lines, 8 functions
- `Tests/InfiniteBrainTests/IndexRebuilderTests.swift` — 39 lines, 1 functions
- `Tests/InfiniteBrainTests/LongInputIngestTests.swift` — 65 lines, 2 functions
- `Tests/InfiniteBrainTests/NodeTypeTests.swift` — 21 lines, 3 functions
- `Tests/InfiniteBrainTests/OrchestratorEmbeddingTests.swift` — 60 lines, 1 functions
- `Tests/InfiniteBrainTests/OrchestratorTests.swift` — 69 lines, 2 functions
- `Tests/InfiniteBrainTests/OrphanedSourceReingestTests.swift` — 60 lines, 2 functions
- `Tests/InfiniteBrainTests/PerSourceFolderTests.swift` — 61 lines, 2 functions
- `Tests/InfiniteBrainTests/Phase6OptimizationTests.swift` — 47 lines, 2 functions
- `Tests/InfiniteBrainTests/Phase7OptimizationTests.swift` — 48 lines, 2 functions
- `Tests/InfiniteBrainTests/Phase8ConcurrencyTests.swift` — 37 lines, 2 functions
- `Tests/InfiniteBrainTests/Phase9DynamicTaxonomyTests.swift` — 31 lines, 2 functions
- `Tests/InfiniteBrainTests/QueryTwoPassTests.swift` — 106 lines, 4 functions
- `Tests/InfiniteBrainTests/ResumeIntegrationTests.swift` — 111 lines, 5 functions
- `Tests/InfiniteBrainTests/SourceNoteTests.swift` — 40 lines, 1 functions
- `Tests/InfiniteBrainTests/TestSupport.swift` — 143 lines, 12 functions
- `Tests/InfiniteBrainTests/TextChunkerTests.swift` — 58 lines, 6 functions
- `Tests/InfiniteBrainTests/VaultInitializerTests.swift` — 27 lines, 2 functions
- `Tests/InfiniteBrainTests/VaultStoreTests.swift` — 76 lines, 3 functions
- `scratch/test_chunker.swift` — 71 lines, 2 functions
- `scratch/test_pdf.swift` — 14 lines, 0 functions

### View (9 files)

- `Sources/InfiniteBrain/CoreUI/MarkdownPreview.swift` — 81 lines, 8 functions
- `Sources/InfiniteBrain/Features/CodeGraph/CodeGraphView.swift` — 537 lines, 8 functions
- `Sources/InfiniteBrain/Features/Dashboard/IngestView.swift` — 288 lines, 4 functions
- `Sources/InfiniteBrain/Features/DraftingSuite/DraftingSetupView.swift` — 351 lines, 0 functions
- `Sources/InfiniteBrain/Features/Help/HelpView.swift` — 408 lines, 11 functions
- `Sources/InfiniteBrain/Features/Help/SchemaView.swift` — 9 lines, 1 functions
- `Sources/InfiniteBrain/Features/KnowledgeGraph/GraphView.swift` — 282 lines, 5 functions
- `Sources/InfiniteBrain/Features/QueryEngine/QueryView.swift` — 148 lines, 0 functions
- `Sources/InfiniteBrain/Features/Settings/SettingsView.swift` — 192 lines, 3 functions

### ViewModel (3 files)

- `Sources/InfiniteBrainCore/ViewModels/DraftingViewModel.swift` — 305 lines, 16 functions
- `Sources/InfiniteBrainCore/ViewModels/IngestViewModel.swift` — 298 lines, 15 functions
- `Sources/InfiniteBrainCore/ViewModels/QueryViewModel.swift` — 81 lines, 1 functions

### Web (3 files)

- `Sources/InfiniteBrainCore/Resources/web/auto-render.min.js` — 1 lines, 1 functions
- `Sources/InfiniteBrainCore/Resources/web/katex.min.js` — 1 lines, 1 functions
- `Sources/InfiniteBrainCore/Resources/web/marked.min.js` — 6 lines, 1 functions

---
*Auto-generated by InfiniteBrain · regenerate with Generate Graph*