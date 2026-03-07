import Foundation

extension CodeReviewAuditService {
    static func scopedExistingFiles(
        _ scopeFiles: [String],
        workspacePath: URL
    ) -> [String] {
        scopeFiles
            .map(normalizedRelativePath)
            .filter { !($0 as NSString).isAbsolutePath }
            .filter {
                FileManager.default.fileExists(
                    atPath: workspacePath.appendingPathComponent($0).path
                )
            }
    }

    static func normalizedRelativePath(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value
    }

    static func loadLines(
        for relativePath: String,
        workspacePath: URL
    ) -> [String]? {
        let fileURL = workspacePath.appendingPathComponent(relativePath)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        return content.components(separatedBy: .newlines)
    }

    static func makeFinding(
        severity: FindingSeverity,
        category: FindingCategory,
        origin: FindingOrigin,
        filePath: String,
        lineNumber: Int?,
        message: String,
        suggestedFix: String,
        confidence: Double,
        evidence: String,
        sourceTool: String,
        blocking: Bool? = nil
    ) -> CodeReviewFinding {
        CodeReviewFinding(
            severity: severity,
            category: category,
            origin: origin,
            filePath: filePath,
            lineNumber: lineNumber,
            message: message,
            suggestedFix: suggestedFix,
            confidence: confidence,
            evidence: evidence,
            sourceTool: sourceTool,
            blocking: blocking
        )
    }

    static func commandOutput(
        executable: String,
        arguments: [String],
        currentDirectoryURL: URL,
        timeoutSeconds: TimeInterval = 8
    ) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutBuffer = StreamCaptureState()
        let stderrBuffer = StreamCaptureState()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let timeoutItem = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + max(1, timeoutSeconds),
            execute: timeoutItem
        )

        process.waitUntilExit()
        timeoutItem.cancel()

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

        let data = stdoutBuffer.data + stderrBuffer.data
        let output = String(data: data, encoding: .utf8) ?? ""
        return (status: process.terminationStatus, output: output)
    }

    static func findProjectFiles(
        named fileName: String,
        workspacePath: URL
    ) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: workspacePath,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var matches: [String] = []
        while let item = enumerator.nextObject() as? URL {
            if item.lastPathComponent == fileName {
                matches.append(item.path.replacingOccurrences(of: workspacePath.path + "/", with: ""))
            }
        }
        return matches.sorted()
    }

    static func gitHistoryFileCounts(
        workspacePath: URL
    ) -> [String: Int] {
        guard let result = commandOutput(
            executable: "/usr/bin/git",
            arguments: ["log", "--since=90.days", "--name-only", "--pretty=format:"],
            currentDirectoryURL: workspacePath
        ), result.status == 0 else {
            return [:]
        }

        var counts: [String: Int] = [:]
        for line in result.output.components(separatedBy: .newlines) {
            let trimmed = normalizedRelativePath(line)
            guard !trimmed.isEmpty else { continue }
            counts[trimmed, default: 0] += 1
        }
        return counts
    }
}

private final class StreamCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}
