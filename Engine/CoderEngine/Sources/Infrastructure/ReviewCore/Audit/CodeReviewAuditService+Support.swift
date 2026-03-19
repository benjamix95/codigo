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

    /// Files that belong to the audit service itself and should be excluded
    /// from pattern scanning to avoid false positives (the audit source contains
    /// the very pattern strings it searches for).
    static let auditSelfExclusionSuffixes: [String] = [
        "CodeReviewAuditService+Bug.swift",
        "CodeReviewAuditService+Security.swift",
        "CodeReviewAuditService+Support.swift",
        "CodeReviewAuditService.swift",
        "CodeReviewAuditModels.swift",
    ]

    static func isAuditSourceFile(_ path: String) -> Bool {
        auditSelfExclusionSuffixes.contains { path.hasSuffix($0) }
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
            arguments: ["log", "--since=90.days.ago", "--name-only", "--pretty=format:"],
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

    static func correlateFindings(_ findings: [CodeReviewFinding]) -> [ReviewAuditCorrelationCluster] {
        let groups = Dictionary(grouping: findings) { finding in
            let prefix = finding.message.split(separator: ".").first.map(String.init) ?? finding.message
            return "\(finding.category.rawValue)|\(prefix.lowercased())"
        }
        return groups.enumerated().map { index, element in
            let files = Array(Set(element.value.map(\.filePath))).sorted()
            let avgConfidence = element.value.compactMap(\.confidence).reduce(0, +) / Double(max(element.value.compactMap(\.confidence).count, 1))
            return ReviewAuditCorrelationCluster(
                id: "cluster-\(index + 1)",
                title: element.key.components(separatedBy: "|").last ?? "cluster",
                files: files,
                findingIDs: element.value.map(\.id),
                confidence: avgConfidence
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    static func runProfile(
        named profile: ReviewAuditProfile,
        scopeFiles: [String],
        workspacePath: URL
    ) -> [ReviewAuditToolResult] {
        switch profile {
        case .quick:
            return [
                runTool(named: ReviewAuditToolName.securityPatterns, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugDiffRisks, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugTestImpact, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        case .securityDeep:
            return ReviewAuditToolName.securityTools.map {
                runTool(named: $0, scopeFiles: scopeFiles, workspacePath: workspacePath)
            }
        case .bugHuntDeep:
            return ReviewAuditToolName.bugTools.map {
                runTool(named: $0, scopeFiles: scopeFiles, workspacePath: workspacePath)
            }
        case .releaseGate:
            return [
                runTool(named: ReviewAuditToolName.securitySupplyChain, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugDiffSemantics, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugTestImpact, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        case .iosPreflight:
            return [
                runTool(named: ReviewAuditToolName.securitySurface, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.securityCrypto, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugConcurrency, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        case .backendRegression:
            return [
                runTool(named: ReviewAuditToolName.securityDataflow, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugErrorHandling, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugAPIContracts, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugDiffSemantics, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        }
    }

    static func correlateResults(
        _ results: [ReviewAuditToolResult],
        summaryPrefix: String
    ) -> ReviewAuditToolResult {
        let findings = deduplicate(results.flatMap(\.findings))
        let clusters = correlateFindings(findings)
        let adapters = Array(Set(results.flatMap(\.adaptersUsed))).sorted()
        let hints = Array(Set(results.flatMap(\.verificationHints))).sorted()
        let metadata: [String: String] = [
            "signal_type": "multi_signal",
            "verification_hint": hints.joined(separator: " | "),
            "promotion_gate": "strict_verified",
            "behavioral_impact": findings.contains(where: \.blocking) ? "high_risk" : "mixed",
        ]
        return ReviewAuditToolResult(
            toolName: ReviewAuditToolName.correlateFindings,
            findings: findings,
            durationMs: max(1, results.reduce(0) { $0 + $1.durationMs }),
            coverageAvailable: results.contains(where: \.coverageAvailable),
            summary: "\(summaryPrefix): \(findings.count) finding(s), \(clusters.count) cluster(s).",
            adaptersUsed: adapters,
            verificationHints: hints,
            metadata: metadata,
            clusters: clusters
        )
    }
}

private final class StreamCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        lock.withLock { _data }
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            _data.append(chunk)
        }
    }
}
