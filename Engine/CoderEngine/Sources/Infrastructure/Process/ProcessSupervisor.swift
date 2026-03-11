import Foundation

public struct ProcessExecutionResult: Sendable, Equatable {
    public let terminationStatus: Int32
    public let stdout: String
    public let stderr: String
    public let metrics: ProcessLifecycleMetrics

    public var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}

public enum ProcessSupervisorError: LocalizedError {
    case launchFailed(String)
    case timedOut(TimeInterval, partialOutput: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        case .timedOut(let timeout, let partialOutput):
            let output = partialOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "Process timed out after \(timeout)s."
            }
            return "Process timed out after \(timeout)s.\n\nPartial output:\n\(output)"
        }
    }
}

public final class ManagedProcessHandle: @unchecked Sendable {
    public let process: Process
    private let startedAt = Date()
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let stateLock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private let exitSemaphore = DispatchSemaphore(value: 0)

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, toStdout: true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, toStdout: false)
        }
        process.terminationHandler = { [weak self] _ in
            self?.exitSemaphore.signal()
        }
    }

    fileprivate func waitForExit(timeout: TimeInterval?) -> Bool {
        let deadline = timeout.map { DispatchTime.now() + $0 } ?? .distantFuture
        return exitSemaphore.wait(timeout: deadline) == .success
    }

    fileprivate func snapshotOutput() -> ProcessExecutionResult {
        finishReading()
        let finishedAt = Date()
        return ProcessExecutionResult(
            terminationStatus: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            metrics: ProcessLifecycleMetrics(
                startedAt: startedAt,
                finishedAt: finishedAt,
                durationMs: max(Int(finishedAt.timeIntervalSince(startedAt) * 1000), 0),
                timedOut: false,
                terminatedBySupervisor: false,
                stdoutBytes: stdoutData.count,
                stderrBytes: stderrData.count
            )
        )
    }

    fileprivate func partialCombinedOutput() -> String {
        finishReading()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return [stdout, stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    fileprivate func closeDescriptors() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutPipe.fileHandleForReading.closeFile()
        stderrPipe.fileHandleForReading.closeFile()
    }

    private func append(_ data: Data, toStdout: Bool) {
        guard !data.isEmpty else { return }
        stateLock.lock()
        if toStdout {
            stdoutData.append(data)
        } else {
            stderrData.append(data)
        }
        stateLock.unlock()
    }

    private func finishReading() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: true)
        append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), toStdout: false)
    }
}

public enum ProcessSupervisor {
    public static func spawn(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> ManagedProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let handle = ManagedProcessHandle(
            process: process,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )

        do {
            try process.run()
            return handle
        } catch {
            handle.closeDescriptors()
            throw ProcessSupervisorError.launchFailed(error.localizedDescription)
        }
    }

    public static func collectOutput(
        from handle: ManagedProcessHandle,
        timeout: TimeInterval? = nil
    ) throws -> ProcessExecutionResult {
        guard handle.waitForExit(timeout: timeout) else {
            terminate(handle, waitForExit: false)
            let partial = handle.partialCombinedOutput()
            handle.closeDescriptors()
            throw ProcessSupervisorError.timedOut(timeout ?? 0, partialOutput: partial)
        }

        let result = handle.snapshotOutput()
        handle.closeDescriptors()
        return result
    }

    public static func terminate(_ handle: ManagedProcessHandle, waitForExit: Bool) {
        if handle.process.isRunning {
            handle.process.terminate()
        }
        if waitForExit {
            _ = handle.waitForExit(timeout: 1.0)
        }
    }

    public static func collectOutputAsync(
        from handle: ManagedProcessHandle,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessExecutionResult {
        try await Task.detached(priority: .utility) {
            try collectOutput(from: handle, timeout: timeout)
        }.value
    }

    public static func runCollecting(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessExecutionResult {
        let handle = try spawn(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
        return try await collectOutputAsync(from: handle, timeout: timeout)
    }

    public static func runCollectingSync(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) throws -> ProcessExecutionResult {
        let handle = try spawn(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
        return try collectOutput(from: handle, timeout: timeout)
    }
}
