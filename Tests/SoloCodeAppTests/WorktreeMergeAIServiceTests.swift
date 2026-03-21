import CoderEngine
import XCTest
@testable import CoderIDE

@MainActor
final class WorktreeMergeAIServiceTests: XCTestCase {
    private var tempDirURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("worktree-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirURL {
            try? FileManager.default.removeItem(at: tempDirURL)
        }
        tempDirURL = nil
        try super.tearDownWithError()
    }

    func testConflictPromptIncludesBranchesAndFiles() {
        let service = WorktreeMergeAIService()
        let prompt = service.conflictResolutionPrompt(
            sourceBranch: "solocode/feature-1",
            targetBranch: "main",
            conflictedFiles: ["Sources/A.swift", "Sources/B.swift"]
        )

        XCTAssertTrue(prompt.contains("solocode/feature-1"))
        XCTAssertTrue(prompt.contains("main"))
        XCTAssertTrue(prompt.contains("Sources/A.swift"))
        XCTAssertTrue(prompt.contains("Sources/B.swift"))
    }

    func testResolveProviderFallsBackToHealthyAgentProvider() throws {
        let registry = ProviderRegistry()
        registry.register(MockWorktreeProvider(id: "openai-api", authenticated: false))
        registry.register(MockWorktreeProvider(id: "codex-cli", authenticated: true))

        let service = WorktreeMergeAIService()
        let provider = try service.resolveProvider(
            preferredProviderId: "openai-api",
            providerRegistry: registry
        )
        XCTAssertEqual(provider.id, "codex-cli")
    }

    func testResolveProviderThrowsWhenNoHealthyProviderExists() {
        let registry = ProviderRegistry()
        registry.register(MockWorktreeProvider(id: "codex-cli", authenticated: false))
        let service = WorktreeMergeAIService()

        XCTAssertThrowsError(
            try service.resolveProvider(preferredProviderId: "codex-cli", providerRegistry: registry)
        )
    }

    func testQualityGateBlocksAutomaticExecutionWithoutManagedRunner() async throws {
        let projectDir = try makeNodeProject(named: "blocked-default-runner")
        let registry = ProviderRegistry()
        registry.register(MockWorktreeProvider(id: "codex-cli", authenticated: true))
        let service = WorktreeMergeAIService()

        do {
            _ = try await service.enforceQualityGate(
                gitRoot: projectDir.path,
                stage: "pre-commit",
                preferredProviderId: "codex-cli",
                providerRegistry: registry,
                maxAttempts: 1
            )
            XCTFail("Expected automatic quality-gate execution to be blocked")
        } catch let error as WorktreeMergeAIServiceError {
            guard case .automaticTestExecutionBlocked = error else {
                return XCTFail("Unexpected worktree error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQualityGateRetriesAndPassesAfterFixRound() async throws {
        let projectDir = try makeNodeProject(named: "retry-pass")
        let processCounter = LockedCounter()
        let promptCounter = LockedCounter()

        let registry = ProviderRegistry()
        let provider = MockWorktreeProvider(id: "codex-cli", authenticated: true)
        registry.register(provider)
        let service = WorktreeMergeAIService(
            processRunner: { _, _, _ in
                let call = processCounter.incrementAndGet()
                if call == 1 {
                    return (1, "", "tests failed")
                }
                return (0, "tests passed", "")
            },
            promptRunner: { _, _, _ in
                _ = promptCounter.incrementAndGet()
                return "fixed"
            }
        )

        let report = try await service.enforceQualityGate(
            gitRoot: projectDir.path,
            stage: "pre-commit",
            preferredProviderId: "codex-cli",
            providerRegistry: registry,
            maxAttempts: 3
        )

        XCTAssertEqual(report.attempts, 2)
        XCTAssertEqual(promptCounter.value, 1)
    }

    func testQualityGateFailsAfterMaxAttempts() async throws {
        let projectDir = try makeNodeProject(named: "always-fail")
        let processCounter = LockedCounter()
        let promptCounter = LockedCounter()

        let registry = ProviderRegistry()
        registry.register(MockWorktreeProvider(id: "codex-cli", authenticated: true))
        let service = WorktreeMergeAIService(
            processRunner: { _, _, _ in
                _ = processCounter.incrementAndGet()
                return (1, "", "tests still failing")
            },
            promptRunner: { _, _, _ in
                _ = promptCounter.incrementAndGet()
                return "attempted-fix"
            }
        )

        await XCTAssertThrowsErrorAsync(
            try await service.enforceQualityGate(
                gitRoot: projectDir.path,
                stage: "post-merge",
                preferredProviderId: "codex-cli",
                providerRegistry: registry,
                maxAttempts: 2
            )
        )
        XCTAssertEqual(processCounter.value, 2)
        XCTAssertEqual(promptCounter.value, 1)
    }

    func testRunHeadlessPromptUsesGenericProviderStreamWithoutCoordinator() async throws {
        let provider = MockWorktreeProvider(id: "codex-cli", authenticated: true)
        let service = WorktreeMergeAIService()

        let result = try await service.runHeadlessPrompt(
            provider: provider,
            gitRoot: tempDirURL.path,
            prompt: "hello"
        )

        XCTAssertEqual(result, "ok")
    }

    private func makeNodeProject(named name: String) throws -> URL {
        let dir = tempDirURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{}\n".write(
            to: dir.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        return dir
    }
}

private final class MockWorktreeProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    private let authenticated: Bool

    init(id: String, authenticated: Bool) {
        self.id = id
        self.displayName = id
        self.authenticated = authenticated
    }

    func isAuthenticated() -> Bool { authenticated }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.textDelta("ok"))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

private final class LockedCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
        return storage
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}
