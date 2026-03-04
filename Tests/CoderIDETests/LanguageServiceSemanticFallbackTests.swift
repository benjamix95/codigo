import Foundation
import XCTest
@testable import CoderIDE
@testable import CoderEngine

final class LanguageServiceSemanticFallbackTests: XCTestCase {
    func testDefinitionFallsBackToLocalIndexWhenSourceKitReturnsEmpty() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("DefinitionSample.swift")
        try """
        struct UserService {
            func run() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let service = try await makeService(workspace: workspace, adapter: EmptySourceKitAdapter())
        let definitions = try await service.goToDefinition(symbol: "UserService")
        XCTAssertFalse(definitions.isEmpty)
        XCTAssertTrue(definitions.allSatisfy { $0.source == .localIndex })
    }

    func testHoverFallsBackToLocalIndexWhenSourceKitReturnsNil() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("HoverFallback.swift")
        try """
        /// User service docs.
        struct UserService {
            func run() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let service = try await makeService(workspace: workspace, adapter: EmptySourceKitAdapter())
        let hover = try await service.hover(symbol: "UserService")
        XCTAssertNotNil(hover)
        XCTAssertEqual(hover?.source, .localIndex)
    }

    func testReferencesFallBackToLocalIndexWhenSourceKitReturnsEmpty() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("ReferencesFallback.swift")
        try """
        struct UserService {}

        struct ClientA {
            let service: UserService
        }

        struct ClientB {
            let service: UserService
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let service = try await makeService(workspace: workspace, adapter: EmptySourceKitAdapter())
        let references = try await service.findReferences(symbol: "UserService")
        XCTAssertFalse(references.isEmpty)
        XCTAssertTrue(references.allSatisfy { $0.source == .localIndex })
    }

    func testRenameFallsBackToLocalIndexWhenSourceKitReturnsNoEdits() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("RenameFallback.swift")
        try """
        struct UserService {}

        struct Client {
            let service: UserService
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let service = try await makeService(workspace: workspace, adapter: EmptySourceKitAdapter())
        let plan = try await service.rename(oldName: "UserService", newName: "AccountService")
        XCTAssertEqual(plan.source, .localIndex)
        XCTAssertFalse(plan.references.isEmpty)
    }

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("language-service-semantic-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    private func makeService(workspace: URL, adapter: LanguageServiceAdapter) async throws -> LanguageService {
        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])
        return LanguageService(
            codebaseIndex: index,
            configuration: LanguageServiceConfiguration(
                languageServiceEnabled: true,
                sourceKitLSPEnabled: true,
                sourceKitLSPPath: "sourcekit-lsp"
            ),
            sourceKitAdapterOverride: adapter
        )
    }
}

private actor EmptySourceKitAdapter: LanguageServiceAdapter {
    nonisolated let source: LanguageServiceSource = .sourceKitLSP

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation] {
        []
    }

    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult? {
        nil
    }

    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation] {
        []
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        LanguageRenamePlan(oldName: oldName, newName: newName, references: [], source: .sourceKitLSP)
    }
}
