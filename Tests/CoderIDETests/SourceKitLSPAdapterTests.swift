import Foundation
import XCTest
@testable import CoderIDE

final class SourceKitLSPAdapterTests: XCTestCase {
    func testSourceKitAdapterEndpointsReturnSourceKitResults() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("Sample.swift")
        try """
        struct UserService {
            func run() {}
        }

        struct Client {
            let service: UserService
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let fileURI = file.absoluteString
        let definitionLocation: [String: Any] = [
            "uri": fileURI,
            "range": [
                "start": ["line": 0, "character": 7],
                "end": ["line": 0, "character": 18]
            ]
        ]
        let referenceLocation: [String: Any] = [
            "uri": fileURI,
            "range": [
                "start": ["line": 5, "character": 17],
                "end": ["line": 5, "character": 28]
            ]
        ]

        let executor = MockSourceKitExecutor(
            responses: [
                "textDocument/definition": try makeJSON([definitionLocation]),
                "textDocument/hover": try makeJSON(["contents": ["kind": "markdown", "value": "UserService docs"]]),
                "workspace/symbol": try makeJSON([["name": "UserService", "location": definitionLocation]]),
                "textDocument/references": try makeJSON([definitionLocation, referenceLocation]),
                "textDocument/rename": try makeJSON([
                    "changes": [
                        fileURI: [[
                            "range": [
                                "start": ["line": 5, "character": 17],
                                "end": ["line": 5, "character": 28]
                            ],
                            "newText": "AccountService"
                        ]]
                    ]
                ])
            ]
        )

        let adapter = SourceKitLSPAdapter(executablePath: "sourcekit-lsp", executor: executor)

        let definitions = try await adapter.goToDefinition(symbol: "UserService", fileHint: file.path)
        XCTAssertEqual(definitions.count, 1)
        XCTAssertEqual(definitions.first?.source, .sourceKitLSP)
        XCTAssertEqual(definitions.first?.line, 1)
        XCTAssertEqual(definitions.first?.column, 8)

        let hover = try await adapter.hover(symbol: "UserService", fileHint: file.path)
        XCTAssertEqual(hover?.source, .sourceKitLSP)
        XCTAssertEqual(hover?.contents, "UserService docs")

        let references = try await adapter.findReferences(symbol: "UserService", limit: 20)
        XCTAssertEqual(references.count, 2)
        XCTAssertTrue(references.allSatisfy { $0.source == .sourceKitLSP })

        let rename = try await adapter.rename(oldName: "UserService", newName: "AccountService")
        XCTAssertEqual(rename.oldName, "UserService")
        XCTAssertEqual(rename.newName, "AccountService")
        XCTAssertEqual(rename.source, .sourceKitLSP)
        XCTAssertEqual(rename.references.count, 1)

        let methods = await executor.recordedMethods()
        XCTAssertTrue(methods.contains("textDocument/definition"))
        XCTAssertTrue(methods.contains("textDocument/hover"))
        XCTAssertTrue(methods.contains("workspace/symbol"))
        XCTAssertTrue(methods.contains("textDocument/references"))
        XCTAssertTrue(methods.contains("textDocument/rename"))
    }

    func testSourceKitAdapterUsesWorkspaceSymbolsWhenFileHintIsMissing() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("NoHint.swift")
        try """
        struct UserService {
            func run() {}
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let fileURI = file.absoluteString
        let definitionLocation: [String: Any] = [
            "uri": fileURI,
            "range": [
                "start": ["line": 0, "character": 7],
                "end": ["line": 0, "character": 18]
            ]
        ]

        let executor = MockSourceKitExecutor(
            responses: [
                "workspace/symbol": try makeJSON([["name": "UserService", "location": definitionLocation]]),
                "textDocument/definition": try makeJSON([definitionLocation]),
                "textDocument/hover": try makeJSON(["contents": "Docs from workspace symbol"])
            ]
        )

        let adapter = SourceKitLSPAdapter(executablePath: "sourcekit-lsp", executor: executor)

        let definitions = try await adapter.goToDefinition(symbol: "UserService", fileHint: nil)
        XCTAssertEqual(definitions.count, 1)
        XCTAssertEqual(definitions.first?.source, .sourceKitLSP)

        let hover = try await adapter.hover(symbol: "UserService", fileHint: nil)
        XCTAssertEqual(hover?.contents, "Docs from workspace symbol")
        XCTAssertEqual(hover?.source, .sourceKitLSP)

        let methods = await executor.recordedMethods()
        XCTAssertEqual(methods.filter { $0 == "workspace/symbol" }.count, 2)
        XCTAssertTrue(methods.contains("textDocument/definition"))
        XCTAssertTrue(methods.contains("textDocument/hover"))
    }

    func testSourceKitAdapterRenameReturnsEmptyPlanForNullWorkspaceEdit() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("RenameNull.swift")
        try """
        struct UserService {}
        """.write(to: file, atomically: true, encoding: .utf8)

        let fileURI = file.absoluteString
        let symbolLocation: [String: Any] = [
            "uri": fileURI,
            "range": [
                "start": ["line": 0, "character": 7],
                "end": ["line": 0, "character": 18]
            ]
        ]

        let executor = MockSourceKitExecutor(
            responses: [
                "workspace/symbol": try makeJSON([["name": "UserService", "location": symbolLocation]]),
                "textDocument/rename": Data("null".utf8)
            ]
        )

        let adapter = SourceKitLSPAdapter(executablePath: "sourcekit-lsp", executor: executor)
        let plan = try await adapter.rename(oldName: "UserService", newName: "AccountService")
        XCTAssertEqual(plan.source, .sourceKitLSP)
        XCTAssertTrue(plan.references.isEmpty)
    }

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("sourcekit-adapter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    private func makeJSON(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }
}

private actor MockSourceKitExecutor: SourceKitLSPRequestExecuting {
    private let responses: [String: Data]
    private var requests: [SourceKitLSPRequest] = []

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func execute(executablePath: String, request: SourceKitLSPRequest) async throws -> Data {
        requests.append(request)
        guard let response = responses[request.method] else {
            throw LanguageServiceError.unsupported("No mock response for \(request.method)")
        }
        return response
    }

    func recordedMethods() -> [String] {
        requests.map(\.method)
    }
}
