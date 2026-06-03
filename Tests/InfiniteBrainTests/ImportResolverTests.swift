import XCTest
@testable import InfiniteBrainCore

final class ImportResolverTests: XCTestCase {
    private let files: Set<String> = [
        "src/foo.ts", "src/bar.tsx", "src/utils/index.ts",
        "utils.py", "models/user.py", "models/__init__.py"
    ]

    func testRelativeTSImportResolved() {
        let imp = RawImport(module: "./bar")
        let result = ImportResolver.resolve(imp, fromFile: "src/foo.ts",
                                            language: "typescript", files: files)
        XCTAssertEqual(result, "src/bar.tsx")
    }

    func testRelativeTSIndexImportResolved() {
        let imp = RawImport(module: "./utils")
        let result = ImportResolver.resolve(imp, fromFile: "src/foo.ts",
                                            language: "typescript", files: files)
        XCTAssertEqual(result, "src/utils/index.ts")
    }

    func testBarePackageReturnsNil() {
        let imp = RawImport(module: "react")
        let result = ImportResolver.resolve(imp, fromFile: "src/foo.ts",
                                            language: "typescript", files: files)
        XCTAssertNil(result)
    }

    func testPythonModuleResolved() {
        let imp = RawImport(module: "models.user")
        let result = ImportResolver.resolve(imp, fromFile: "main.py",
                                            language: "python", files: files)
        XCTAssertEqual(result, "models/user.py")
    }

    func testPythonFromImportResolved() {
        let imp = RawImport(module: "models", name: "user")
        let result = ImportResolver.resolve(imp, fromFile: "main.py",
                                            language: "python", files: files)
        XCTAssertEqual(result, "models/user.py")
    }

    func testSwiftImportReturnsNil() {
        let imp = RawImport(module: "Foundation")
        let result = ImportResolver.resolve(imp, fromFile: "App.swift",
                                            language: "swift", files: files)
        XCTAssertNil(result)
    }

    func testNormalizeDotDot() {
        XCTAssertEqual(ImportResolver.normalize(joining: "src/utils", "../bar"), "src/bar")
    }

    func testNormalizeDot() {
        XCTAssertEqual(ImportResolver.normalize(joining: "src", "./foo"), "src/foo")
    }

    func testAliasImportResolved() {
        let aliases = ["@/": "src/"]
        let imp = RawImport(module: "@/lib/api")
        let result = ImportResolver.resolve(imp, fromFile: "src/components/Card.tsx",
                                            language: "typescript",
                                            files: ["src/lib/api.ts"],
                                            aliases: aliases)
        XCTAssertEqual(result, "src/lib/api.ts")
    }

    func testAliasWithNoMatchStillReturnsNil() {
        let aliases = ["@/": "src/"]
        let imp = RawImport(module: "@/missing/thing")
        let result = ImportResolver.resolve(imp, fromFile: "src/app.ts",
                                            language: "typescript",
                                            files: ["src/other.ts"],
                                            aliases: aliases)
        XCTAssertNil(result)
    }
}
