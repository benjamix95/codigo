import XCTest
@testable import CoderIDE

final class LLDBDAPDebugAdapterTests: XCTestCase {
    func testStartSessionConfiguraRunArgsELaunchNelBatchLLDB() async {
        let runner = LLDBBatchRunnerSpy(
            queuedResults: [
                .init(exitCode: 0, output: "lldb version 17"),
                .init(exitCode: 0, output: """
                Process 123 stopped
                * thread #1, stop reason = breakpoint 1.1
                frame #0: 0x0000000100001111 Demo`main at Sources/Main.swift:12
                """)
            ]
        )
        let adapter = LLDBDAPDebugAdapter(runBatch: { commands in
            await runner.run(commands: commands)
        })

        var inactive = DebugBreakpoint(filePath: "Sources/Other.swift", line: 99)
        inactive.isActive = false
        let state = await adapter.startSession(
            targetPath: "/bin/ls",
            arguments: ["--color=never", "path with spaces"],
            breakpoints: [
                DebugBreakpoint(filePath: "Sources/Main.swift", line: 12, condition: "counter > 0"),
                inactive
            ],
            watchExpressions: ["counter"]
        )

        XCTAssertEqual(state.status, .paused)
        XCTAssertEqual(state.lastCommand, "process launch --stop-at-entry")
        XCTAssertEqual(state.breakpointsCount, 1)

        let launchCommands = await runner.invocation(at: 1)
        XCTAssertTrue(launchCommands.contains(where: { $0.contains("settings set -- target.run-args") }))
        XCTAssertTrue(launchCommands.contains(where: { $0.contains("\"--color=never\" \"path with spaces\"") }))
        XCTAssertTrue(launchCommands.contains("process launch --stop-at-entry"))
        XCTAssertTrue(launchCommands.contains(where: { $0.contains("breakpoint set --file \"Sources/Main.swift\" --line 12") }))
        XCTAssertTrue(launchCommands.contains("expression -- counter"))
    }


    func testStartSessionEscapesTargetPathForLLDBCommand() async {
        let runner = LLDBBatchRunnerSpy(
            queuedResults: [
                .init(exitCode: 0, output: "lldb version 17"),
                .init(exitCode: 0, output: "Process 123 stopped")
            ]
        )
        let adapter = LLDBDAPDebugAdapter(runBatch: { commands in
            await runner.run(commands: commands)
        })

        let temporaryDirectory = FileManager.default.temporaryDirectory
        let targetURL = temporaryDirectory.appendingPathComponent("lldb-target-\"quoted\"\nline")
        FileManager.default.createFile(atPath: targetURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: targetURL) }

        _ = await adapter.startSession(
            targetPath: targetURL.path,
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let launchCommands = await runner.invocation(at: 1)
        let escapedTarget = LLDBDAPDebugAdapterSupport.escapeLLDBString(targetURL.path)
        XCTAssertTrue(launchCommands.contains("target create \(escapedTarget)"))
    }

    func testStepOverEsegueComandoStepNelBatch() async {
        let runner = LLDBBatchRunnerSpy(
            queuedResults: [
                .init(exitCode: 0, output: "lldb version 17"),
                .init(exitCode: 0, output: "Process 200 stopped\nframe #0: 0x1 Demo`main at Sources/Main.swift:10"),
                .init(exitCode: 0, output: "Process 200 stopped\nframe #0: 0x2 Demo`foo at Sources/Foo.swift:21")
            ]
        )
        let adapter = LLDBDAPDebugAdapter(runBatch: { commands in
            await runner.run(commands: commands)
        })

        _ = await adapter.startSession(
            targetPath: "/bin/ls",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let state = await adapter.step(command: "thread step-over")

        XCTAssertEqual(state.status, .paused)
        XCTAssertEqual(state.lastCommand, "thread step-over")

        let stepCommands = await runner.invocation(at: 2)
        XCTAssertTrue(stepCommands.contains("thread step-over"))
    }

    func testContinueImpostaRunningERefreshUsaProcessContinue() async {
        let runner = LLDBBatchRunnerSpy(
            queuedResults: [
                .init(exitCode: 0, output: "lldb version 17"),
                .init(exitCode: 0, output: "Process 300 stopped\nframe #0: 0x1 Demo`main at Sources/Main.swift:10"),
                .init(exitCode: 0, output: "Process 300 state = running"),
                .init(exitCode: 0, output: "Process 300 stopped\nstop reason = breakpoint 1.1")
            ]
        )
        let adapter = LLDBDAPDebugAdapter(runBatch: { commands in
            await runner.run(commands: commands)
        })

        _ = await adapter.startSession(
            targetPath: "/bin/ls",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let continueState = await adapter.step(command: "continue")
        XCTAssertEqual(continueState.status, .running)
        XCTAssertEqual(continueState.lastCommand, "process continue")

        let refreshState = await adapter.refresh()
        XCTAssertEqual(refreshState.status, .paused)
        XCTAssertEqual(refreshState.lastCommand, "refresh")

        let refreshCommands = await runner.invocation(at: 3)
        XCTAssertTrue(refreshCommands.contains("process continue"))
    }

    func testProcessExitedPortaSessioneStoppedESaltaRefreshSuccessivo() async {
        let runner = LLDBBatchRunnerSpy(
            queuedResults: [
                .init(exitCode: 0, output: "lldb version 17"),
                .init(exitCode: 0, output: "Process 404 stopped\nframe #0: 0x1 Demo`main at Sources/Main.swift:10"),
                .init(exitCode: 0, output: "Process 404 exited with status = 0 (0x00000000)")
            ]
        )
        let adapter = LLDBDAPDebugAdapter(runBatch: { commands in
            await runner.run(commands: commands)
        })

        _ = await adapter.startSession(
            targetPath: "/bin/ls",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let exitedState = await adapter.step(command: "thread step-over")
        XCTAssertEqual(exitedState.status, .stopped)

        let callCountBeforeRefresh = await runner.invocationCount()
        let refreshState = await adapter.refresh()
        let callCountAfterRefresh = await runner.invocationCount()

        XCTAssertEqual(refreshState.status, .stopped)
        XCTAssertEqual(callCountBeforeRefresh, callCountAfterRefresh)
    }

    func testPersistentSessionMantieneLoStatoTraStartEStep() async {
        let session = LLDBPersistentSessionSpy(
            queuedOutputs: [
                """
                Process 808 stopped
                * thread #1, stop reason = breakpoint 1.1
                frame #0: 0x1 Demo`main at Sources/Main.swift:10
                """,
                """
                Process 808 stopped
                * thread #1, stop reason = step over
                frame #0: 0x2 Demo`next at Sources/Main.swift:11
                """
            ]
        )
        let adapter = LLDBDAPDebugAdapter(sessionFactory: {
            session
        })

        _ = await adapter.startSession(
            targetPath: "/bin/ls",
            arguments: ["-l"],
            breakpoints: [DebugBreakpoint(filePath: "Sources/Main.swift", line: 10)],
            watchExpressions: ["counter"]
        )
        let step = await adapter.step(command: "thread step-over")

        XCTAssertEqual(step.status, .paused)
        XCTAssertEqual(step.lastCommand, "thread step-over")

        let firstInvocation = await session.invocation(at: 0)
        XCTAssertTrue(firstInvocation.contains(where: { $0.contains("target create") }))
        XCTAssertTrue(firstInvocation.contains("process launch --stop-at-entry"))
        XCTAssertTrue(firstInvocation.contains("process status"))

        let secondInvocation = await session.invocation(at: 1)
        XCTAssertFalse(secondInvocation.contains(where: { $0.contains("target create") }))
        XCTAssertTrue(secondInvocation.contains("thread step-over"))
        XCTAssertTrue(secondInvocation.contains("process status"))
    }
}

private actor LLDBBatchRunnerSpy {
    private var queuedResults: [LLDBDAPDebugAdapter.LLDBBatchExecutionResult]
    private var invocations: [[String]] = []

    init(queuedResults: [LLDBDAPDebugAdapter.LLDBBatchExecutionResult]) {
        self.queuedResults = queuedResults
    }

    func run(commands: [String]) -> LLDBDAPDebugAdapter.LLDBBatchExecutionResult {
        invocations.append(commands)
        if queuedResults.isEmpty {
            return .init(exitCode: 0, output: "")
        }
        return queuedResults.removeFirst()
    }

    func invocation(at index: Int) -> [String] {
        invocations[index]
    }

    func invocationCount() -> Int {
        invocations.count
    }
}

private actor LLDBPersistentSessionSpy: LLDBCommandSession {
    private var queuedOutputs: [String]
    private var invocations: [[String]] = []
    private(set) var closeCalls = 0

    init(queuedOutputs: [String]) {
        self.queuedOutputs = queuedOutputs
    }

    func send(commands: [String]) async throws -> String {
        invocations.append(commands)
        if queuedOutputs.isEmpty {
            return ""
        }
        return queuedOutputs.removeFirst()
    }

    func close() async {
        closeCalls += 1
    }

    func invocation(at index: Int) -> [String] {
        invocations[index]
    }
}
