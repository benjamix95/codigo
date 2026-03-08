import Foundation
import XCTest
@testable import CoderIDE
@testable import CoderEngine
final class LanguageServiceTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("language-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func configuration(
        languageServiceEnabled: Bool = true,
        sourceKitLSPEnabled: Bool = true,
        sourceKitLSPPath: String = "sourcekit-lsp"
    ) -> LanguageServiceConfiguration {
        LanguageServiceConfiguration(
            languageServiceEnabled: languageServiceEnabled,
            sourceKitLSPEnabled: sourceKitLSPEnabled,
            sourceKitLSPPath: sourceKitLSPPath
        )
    }

    func testLanguageServiceFallsBackToLocalIndexWhenSourceKitAdapterFails() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("UserService.swift")
        try """
        struct UserService {
            func fetchUser() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(),
            sourceKitAdapterOverride: FailingLanguageAdapter()
        )

        let definitions = try await service.goToDefinition(symbol: "UserService")
        XCTAssertFalse(definitions.isEmpty)
        XCTAssertEqual(definitions.first?.source, .localIndex)
    }

    func testLanguageServiceConfigurationEnablesSourceKitByDefault() throws {
        let suiteName = "language-service-config-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = LanguageServiceConfiguration.load(from: defaults)
        XCTAssertTrue(config.sourceKitLSPEnabled)
        XCTAssertEqual(config.sourceKitLSPPath, "sourcekit-lsp")
    }

    func testLanguageServiceRenamePlanIncludesReferencesFromFallbackIndex() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("Sample.swift")
        try """
        struct Client {
            let service: UserService
        }

        struct UserService {
            func run() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])
        let service = LanguageService(codebaseIndex: index)

        let renamePlan = try await service.rename(oldName: " UserService ", newName: " AccountService ")
        XCTAssertEqual(renamePlan.oldName, "UserService")
        XCTAssertEqual(renamePlan.newName, "AccountService")
        XCTAssertFalse(renamePlan.references.isEmpty)
        XCTAssertEqual(renamePlan.source, .localIndex)
    }

    func testLanguageServiceHoverFallsBackToLocalIndexWhenSourceKitAdapterFails() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("HoverSample.swift")
        try """
        /// Service used by clients.
        struct UserService {
            func run() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(),
            sourceKitAdapterOverride: FailingLanguageAdapter()
        )

        let hover = try await service.hover(symbol: "UserService")
        XCTAssertNotNil(hover)
        XCTAssertEqual(hover?.source, .localIndex)
        XCTAssertTrue(hover?.contents.contains("UserService") ?? false)
    }

    func testLanguageServiceFindReferencesFallsBackToLocalIndexWhenSourceKitAdapterFails() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("ReferencesSample.swift")
        try """
        struct UserService {}

        struct ClientA {
            let service: UserService
        }

        struct ClientB {
            let service: UserService
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(),
            sourceKitAdapterOverride: FailingLanguageAdapter()
        )

        let references = try await service.findReferences(symbol: "UserService")
        XCTAssertGreaterThanOrEqual(references.count, 2)
        XCTAssertTrue(references.allSatisfy { $0.source == .localIndex })
    }

    func testLanguageServiceDisabledThrows() async throws {
        let index = CodebaseIndex()
        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(languageServiceEnabled: false, sourceKitLSPEnabled: false)
        )

        do {
            _ = try await service.findReferences(symbol: "Any")
            XCTFail("Expected LanguageServiceError.disabled")
        } catch LanguageServiceError.disabled {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLanguageServiceUsesSourceKitResultsWhenAdapterSucceeds() async throws {
        let index = CodebaseIndex()
        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(),
            sourceKitAdapterOverride: SuccessfulLanguageAdapter()
        )

        let definitions = try await service.goToDefinition(symbol: "UserService")
        XCTAssertEqual(definitions.count, 1)
        XCTAssertEqual(definitions.first?.source, .sourceKitLSP)
    }

    func testLanguageServiceFallsBackWhenRealSourceKitAdapterFromConfigurationErrors() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("FallbackSample.swift")
        try """
        struct UserService {}
        struct Client {
            let service: UserService
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(sourceKitLSPPath: "sourcekit-lsp-missing-\(UUID().uuidString)")
        )

        let references = try await service.findReferences(symbol: "UserService")
        XCTAssertFalse(references.isEmpty)
        XCTAssertTrue(references.allSatisfy { $0.source == .localIndex })
    }

    func testLanguageServiceUsesLocalResultsWhenSourceKitFeatureFlagIsOff() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("DefinitionFlagOff.swift")
        try """
        struct UserService {}
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(sourceKitLSPEnabled: false),
            sourceKitAdapterOverride: SuccessfulLanguageAdapter()
        )

        let definitions = try await service.goToDefinition(symbol: "UserService")
        XCTAssertFalse(definitions.isEmpty)
        XCTAssertTrue(definitions.allSatisfy { $0.source == .localIndex })
        let resolvedPath = try XCTUnwrap(definitions.first?.filePath)
        XCTAssertTrue(
            resolvedPath == file.path ||
            resolvedPath.hasSuffix("\(workspace.lastPathComponent)/\(file.lastPathComponent)")
        )
    }

    func testLanguageServiceFallsBackWhenSourceKitReturnsNilHover() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("HoverFallback.swift")
        try """
        /// User service docs.
        struct UserService {}
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(),
            sourceKitAdapterOverride: EmptyLanguageAdapter()
        )

        let hover = try await service.hover(symbol: "UserService")
        XCTAssertNotNil(hover)
        XCTAssertEqual(hover?.source, .localIndex)
    }

    func testLanguageServiceRenameUsesSourceKitPlanWhenAdapterReturnsReferences() async throws {
        let index = CodebaseIndex()
        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(sourceKitLSPEnabled: true),
            sourceKitAdapterOverride: SuccessfulLanguageAdapter()
        )

        let rename = try await service.rename(oldName: " UserService ", newName: " AccountService ")
        XCTAssertEqual(rename.oldName, "UserService")
        XCTAssertEqual(rename.newName, "AccountService")
        XCTAssertEqual(rename.source, .sourceKitLSP)
        XCTAssertFalse(rename.references.isEmpty)
        XCTAssertTrue(rename.references.allSatisfy { $0.source == .sourceKitLSP })
    }

    func testLanguageServiceFallsBackWhenSourceKitRenameHasNoReferences() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("RenameFallback.swift")
        try """
        struct UserService {}
        struct Client {
            let service: UserService
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let service = LanguageService(
            codebaseIndex: index,
            configuration: configuration(),
            sourceKitAdapterOverride: EmptyLanguageAdapter()
        )

        let rename = try await service.rename(oldName: " UserService ", newName: " AccountService ")
        XCTAssertEqual(rename.oldName, "UserService")
        XCTAssertEqual(rename.newName, "AccountService")
        XCTAssertFalse(rename.references.isEmpty)
        XCTAssertEqual(rename.source, .localIndex)
    }
}
