import Foundation
import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testFindSymbolKeepsKindAndFuzzyContractWhenLanguageServiceIsPresent() async throws {
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sourceFile = tmp.appendingPathComponent("SymbolContract.swift")
        try """
        struct QueryContract {}

        func QueryContractHelper() {}
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [tmp])

        let languageService = TrackingRuntimeLanguageService(
            goToDefinitionResults: [
                RuntimeLanguageLocation(
                    filePath: "/tmp/InjectedByLanguageService.swift",
                    line: 1,
                    column: 1,
                    symbolName: "InjectedByLanguageService",
                    source: .sourceKitLSP
                )
            ],
            findReferencesResults: [],
            renamePlan: RuntimeLanguageRenamePlan(
                oldName: "QueryContract",
                newName: "Renamed",
                references: [],
                source: .sourceKitLSP
            )
        )

        let runtime = UnifiedToolRuntime(
            index: index,
            workspacePaths: [tmp],
            languageService: languageService
        )
        let (call, ctx) = makeCall(
            name: "find_symbol",
            args: [
                "query": "QueryContractHel",
                "kind": "function",
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let payload = extractLastPayload(events)

        XCTAssertEqual(payload?["status"], "completed")
        XCTAssertTrue((payload?["output"] ?? "").contains("QueryContractHelper"))
        XCTAssertFalse((payload?["output"] ?? "").contains("InjectedByLanguageService"))
        let goToDefinitionCalls = await languageService.goToDefinitionCallCount()
        XCTAssertEqual(goToDefinitionCalls, 0)
    }

    func testRenameFallbackParsesFindReferencesLanguageServiceOutput() async throws {
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let ignored = tmp.appendingPathComponent("Ignored.swift")
        try """
        struct UserService {}

        struct Client {
            let service: UserService
        }
        """.write(to: ignored, atomically: true, encoding: .utf8)
        try "Ignored.swift\n".write(
            to: tmp.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [tmp])

        let languageService = TrackingRuntimeLanguageService(
            goToDefinitionResults: [],
            findReferencesResults: [
                RuntimeLanguageLocation(
                    filePath: ignored.path,
                    line: 1,
                    column: 1,
                    symbolName: "UserService",
                    source: .sourceKitLSP
                )
            ],
            renamePlan: RuntimeLanguageRenamePlan(
                oldName: "UserService",
                newName: "AccountService",
                references: [],
                source: .sourceKitLSP
            )
        )

        let runtime = UnifiedToolRuntime(
            index: index,
            workspacePaths: [tmp],
            languageService: languageService
        )
        let (call, ctx) = makeCall(
            name: "rename_symbol",
            args: [
                "query": "UserService",
                "new_name": "AccountService",
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let payload = extractLastPayload(events)

        XCTAssertEqual(payload?["status"], "completed")
        XCTAssertTrue((payload?["detail"] ?? "").contains("Renamed 'UserService'"))
        let renameCalls = await languageService.renameCallCount()
        let findReferencesCalls = await languageService.findReferencesCallCount()
        XCTAssertEqual(renameCalls, 1)
        XCTAssertEqual(findReferencesCalls, 1)

        let updated = try String(contentsOf: ignored, encoding: .utf8)
        XCTAssertTrue(updated.contains("AccountService"))
        XCTAssertFalse(updated.contains("UserService"))
    }

    func testRenameFallbackIgnoresOutOfWorkspaceAbsolutePaths() async throws {
        let workspace = try makeTmpWorkspace()
        let external = try makeTmpWorkspace()
        defer {
            try? FileManager.default.removeItem(at: workspace)
            try? FileManager.default.removeItem(at: external)
        }

        let workspaceFile = workspace.appendingPathComponent("Workspace.swift")
        try "struct UserService {}\n".write(to: workspaceFile, atomically: true, encoding: .utf8)

        let outsideFile = external.appendingPathComponent("Outside.swift")
        try "struct UserService {}\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])

        let languageService = TrackingRuntimeLanguageService(
            goToDefinitionResults: [],
            findReferencesResults: [
                RuntimeLanguageLocation(
                    filePath: workspaceFile.path,
                    line: 1,
                    column: 1,
                    symbolName: "UserService",
                    source: .sourceKitLSP
                ),
                RuntimeLanguageLocation(
                    filePath: outsideFile.path,
                    line: 1,
                    column: 1,
                    symbolName: "UserService",
                    source: .sourceKitLSP
                ),
            ],
            renamePlan: RuntimeLanguageRenamePlan(
                oldName: "UserService",
                newName: "AccountService",
                references: [],
                source: .sourceKitLSP
            )
        )

        let runtime = UnifiedToolRuntime(
            index: index,
            workspacePaths: [workspace],
            languageService: languageService
        )
        let (call, ctx) = makeCall(
            name: "rename_symbol",
            args: [
                "query": "UserService",
                "new_name": "AccountService",
            ],
            workspace: workspace
        )
        let events = await runtime.execute(call, context: ctx)
        let payload = extractLastPayload(events)

        XCTAssertEqual(payload?["status"], "completed")

        let updatedWorkspace = try String(contentsOf: workspaceFile, encoding: .utf8)
        XCTAssertTrue(updatedWorkspace.contains("AccountService"))
        XCTAssertFalse(updatedWorkspace.contains("UserService"))

        let updatedOutside = try String(contentsOf: outsideFile, encoding: .utf8)
        XCTAssertTrue(updatedOutside.contains("UserService"))
        XCTAssertFalse(updatedOutside.contains("AccountService"))
    }
}

private actor TrackingRuntimeLanguageService: RuntimeLanguageService {
    private let goToDefinitionResults: [RuntimeLanguageLocation]
    private let findReferencesResults: [RuntimeLanguageLocation]
    private let plannedRename: RuntimeLanguageRenamePlan

    private var goToDefinitionCalls = 0
    private var findReferencesCalls = 0
    private var renameCalls = 0

    init(
        goToDefinitionResults: [RuntimeLanguageLocation],
        findReferencesResults: [RuntimeLanguageLocation],
        renamePlan: RuntimeLanguageRenamePlan
    ) {
        self.goToDefinitionResults = goToDefinitionResults
        self.findReferencesResults = findReferencesResults
        self.plannedRename = renamePlan
    }

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [RuntimeLanguageLocation] {
        goToDefinitionCalls += 1
        return goToDefinitionResults
    }

    func findReferences(symbol: String, limit: Int) async throws -> [RuntimeLanguageLocation] {
        findReferencesCalls += 1
        return Array(findReferencesResults.prefix(limit))
    }

    func rename(oldName: String, newName: String) async throws -> RuntimeLanguageRenamePlan {
        renameCalls += 1
        return RuntimeLanguageRenamePlan(
            oldName: oldName,
            newName: newName,
            references: plannedRename.references,
            source: plannedRename.source
        )
    }

    func goToDefinitionCallCount() -> Int { goToDefinitionCalls }
    func findReferencesCallCount() -> Int { findReferencesCalls }
    func renameCallCount() -> Int { renameCalls }
}
