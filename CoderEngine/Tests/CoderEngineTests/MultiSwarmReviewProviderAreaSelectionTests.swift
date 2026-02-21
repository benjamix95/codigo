import Foundation
import XCTest
@testable import CoderEngine

private final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    var isAuthenticatedValue: Bool = true
    var onSend: @Sendable (String) -> [StreamEvent]

    init(id: String = "mock", displayName: String = "Mock", onSend: @escaping @Sendable (String) -> [StreamEvent]) {
        self.id = id
        self.displayName = displayName
        self.onSend = onSend
    }

    func isAuthenticated() -> Bool { isAuthenticatedValue }

    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let events = onSend(prompt)
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

final class MultiSwarmReviewProviderAreaSelectionTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("UI"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Core"), withIntermediateDirectories: true)
        try "struct A {}".write(to: dir.appendingPathComponent("UI/View.swift"), atomically: true, encoding: .utf8)
        try "struct B {}".write(to: dir.appendingPathComponent("Core/Model.swift"), atomically: true, encoding: .utf8)
        return dir
    }

    private func collectText(from stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> String {
        var text = ""
        for try await event in stream {
            if case .textDelta(let delta) = event {
                text += delta
            }
        }
        return text
    }

    func testAnalysisRequestsAreaSelection() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mock = MockLLMProvider { prompt in
            if prompt.contains("Sei un orchestratore di code review") {
                return [.textDelta("""
                {"areas":[{"id":"area-1","label":"UI","partitionIds":["p0"],"fileHints":["UI/View.swift"],"severity":"alta","highlights":["bug UI"]}],"summary":"Riepilogo"}
                """)]
            }
            return [.textDelta("priorità alta: bug trovato")]
        }

        let provider = MultiSwarmReviewProvider(
            config: MultiSwarmReviewConfig(partitionCount: 2, enabledPhases: .analysisAndExecution, analysisBackend: "codex", executionBackend: "openai-api"),
            codexProvider: CodexCLIProvider(codexPath: "/bin/echo"),
            executionProvider: mock,
            analysisProviderOverride: mock
        )

        let context = WorkspaceContext(workspacePath: workspace)
        let stream = try await provider.send(prompt: "fai review completa", context: context, imageURLs: nil)
        let text = try await collectText(from: stream)

        XCTAssertTrue(text.contains("Fase 1: Analisi multi-swarm"))
        XCTAssertTrue(text.contains("Raggruppamento aree"))
        XCTAssertTrue(text.contains("focus area <id>"))
    }

    func testApplySingleAreaSelectionRunsFixesAndRequestsResidualSelection() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mock = MockLLMProvider { prompt in
            if prompt.contains("Sei un orchestratore di code review") {
                return [.textDelta("""
                {"areas":[{"id":"area-1","label":"UI","partitionIds":["p0"],"fileHints":["UI/View.swift"],"severity":"alta","highlights":["bug UI"]},{"id":"area-2","label":"Core","partitionIds":["p1"],"fileHints":["Core/Model.swift"],"severity":"media","highlights":["warning core"]}],"summary":"Due aree"}
                """)]
            }
            if prompt.contains("applica le correzioni") {
                return [.textDelta("fix applicato")]
            }
            return [.textDelta("bug trovato")]
        }

        let provider = MultiSwarmReviewProvider(
            config: MultiSwarmReviewConfig(partitionCount: 2, enabledPhases: .analysisAndExecution, analysisBackend: "codex", executionBackend: "openai-api"),
            codexProvider: CodexCLIProvider(codexPath: "/bin/echo"),
            executionProvider: mock,
            analysisProviderOverride: mock
        )

        let context = WorkspaceContext(workspacePath: workspace)
        _ = try await collectText(from: try await provider.send(prompt: "review", context: context, imageURLs: nil))
        let second = try await provider.send(prompt: "focus area 1", context: context, imageURLs: nil)
        let text = try await collectText(from: second)

        XCTAssertTrue(text.contains("Fase 2: Esecuzione correzioni"))
        XCTAssertTrue(text.contains("Area completata"))
        XCTAssertTrue(text.contains("focus area <id>"))
    }

    func testApplyAllSelectionCompletesSession() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mock = MockLLMProvider { prompt in
            if prompt.contains("Sei un orchestratore di code review") {
                return [.textDelta("""
                {"areas":[{"id":"area-1","label":"UI","partitionIds":["p0"],"fileHints":[],"severity":"alta","highlights":["bug"]}],"summary":"ok"}
                """)]
            }
            return [.textDelta("output")]
        }

        let provider = MultiSwarmReviewProvider(
            config: MultiSwarmReviewConfig(partitionCount: 2, enabledPhases: .analysisAndExecution, analysisBackend: "codex", executionBackend: "openai-api"),
            codexProvider: CodexCLIProvider(codexPath: "/bin/echo"),
            executionProvider: mock,
            analysisProviderOverride: mock
        )

        let context = WorkspaceContext(workspacePath: workspace)
        _ = try await collectText(from: try await provider.send(prompt: "review", context: context, imageURLs: nil))
        let text = try await collectText(from: try await provider.send(prompt: "focus tutte", context: context, imageURLs: nil))

        XCTAssertTrue(text.contains("Correzioni completate"))
    }

    func testSelectionWithoutSessionReturnsGuidance() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mock = MockLLMProvider { _ in [.textDelta("noop")] }
        let provider = MultiSwarmReviewProvider(
            config: MultiSwarmReviewConfig(partitionCount: 2, enabledPhases: .analysisAndExecution),
            codexProvider: CodexCLIProvider(codexPath: "/bin/echo"),
            executionProvider: mock,
            analysisProviderOverride: mock
        )

        let context = WorkspaceContext(workspacePath: workspace)
        let text = try await collectText(from: try await provider.send(prompt: "focus area 1", context: context, imageURLs: nil))

        XCTAssertTrue(text.contains("Nessuna sessione review attiva"))
    }

    func testOrchestratorCanReturnNoAreasAndSelectionIsOptional() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let mock = MockLLMProvider { prompt in
            if prompt.contains("Sei un orchestratore di code review") {
                return [.textDelta("{" + "\"areas\":[],\"summary\":\"Nessuna segmentazione utile\"" + "}")]
            }
            return [.textDelta("finding")]
        }

        let provider = MultiSwarmReviewProvider(
            config: MultiSwarmReviewConfig(partitionCount: 2, enabledPhases: .analysisAndExecution),
            codexProvider: CodexCLIProvider(codexPath: "/bin/echo"),
            executionProvider: mock,
            analysisProviderOverride: mock
        )

        let context = WorkspaceContext(workspacePath: workspace)
        let text = try await collectText(from: try await provider.send(prompt: "review", context: context, imageURLs: nil))

        XCTAssertTrue(text.contains("Nessuna area separata necessaria"))
        XCTAssertTrue(text.contains("focus tutte"))
    }
}
