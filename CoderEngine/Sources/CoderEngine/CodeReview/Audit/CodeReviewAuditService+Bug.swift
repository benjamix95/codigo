import Foundation

extension CodeReviewAuditService {
    static func runBugDiffRisksAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let patterns: [(needle: String, severity: FindingSeverity, category: FindingCategory, message: String, remediation: String, confidence: Double)] = [
            ("fatalError(", .critical, .regression, "fatalError in changed code can crash at runtime.", "Replace fatalError with recoverable error handling or an asserted precondition only in unreachable paths.", 0.90),
            ("try!", .warning, .correctness, "Force-try can turn recoverable failures into runtime crashes.", "Handle the throwing call explicitly and propagate or recover from the error.", 0.82),
            (" as! ", .warning, .correctness, "Forced cast introduces crash risk on unexpected input.", "Use a safe cast with graceful fallback or explicit validation.", 0.79),
            ("DispatchQueue.main.sync", .critical, .concurrency, "Synchronous dispatch to the main queue risks deadlock.", "Avoid synchronous main-queue dispatch and restructure the call flow.", 0.93),
            ("Thread.sleep(", .warning, .regression, "Thread.sleep in application code risks blocking and flaky timing.", "Use async waiting primitives or explicit scheduling instead of sleeping threads.", 0.77),
        ]

        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (index, line) in lines.enumerated() {
                for pattern in patterns where line.contains(pattern.needle) {
                    findings.append(
                        makeFinding(
                            severity: pattern.severity,
                            category: pattern.category,
                            origin: .bugHunter,
                            filePath: file,
                            lineNumber: index + 1,
                            message: pattern.message,
                            suggestedFix: pattern.remediation,
                            confidence: pattern.confidence,
                            evidence: line.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceTool: ReviewAuditToolName.bugDiffRisks,
                            blocking: pattern.severity == .critical
                        )
                    )
                }
            }
        }

        let summary = findings.isEmpty
            ? "No obvious crash or regression-risk patterns detected in scoped files."
            : "Detected \(findings.count) bug-risk pattern(s) in scoped files."
        return (findings, !scopeFiles.isEmpty, summary)
    }

    static func runBugTestGapsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let sourceFiles = scopeFiles.filter { !$0.lowercased().contains("test") }
        guard !sourceFiles.isEmpty else {
            return ([], !scopeFiles.isEmpty, "No non-test files in scope for test-gap audit.")
        }

        let scopedSet = Set(scopeFiles.map { $0.lowercased() })
        var findings: [CodeReviewFinding] = []
        for file in sourceFiles {
            let fileName = (file as NSString).lastPathComponent
            let stem = ((fileName as NSString).deletingPathExtension as NSString).lastPathComponent
            let candidateTestNames = [
                "\(stem)Tests.swift",
                "\(stem).test.ts",
                "\(stem).spec.ts",
                "test_\(stem.lowercased()).py",
            ]
            let hasScopedTest = candidateTestNames.contains { candidate in
                scopedSet.contains(candidate.lowercased())
                    || scopedSet.contains("tests/\(candidate.lowercased())")
            }
            let projectMatches = candidateTestNames.flatMap {
                findProjectFiles(named: $0, workspacePath: workspacePath)
            }
            if hasScopedTest || !projectMatches.isEmpty {
                continue
            }

            findings.append(
                makeFinding(
                    severity: .suggestion,
                    category: .tests,
                    origin: .bugHunter,
                    filePath: file,
                    lineNumber: nil,
                    message: "Changed source file has no obvious paired test coverage.",
                    suggestedFix: "Add or update targeted tests covering the modified behavior and edge cases.",
                    confidence: 0.66,
                    evidence: "No matching test file found for \(fileName).",
                    sourceTool: ReviewAuditToolName.bugTestGaps,
                    blocking: false
                )
            )
        }

        let summary = findings.isEmpty
            ? "No obvious test coverage gaps detected for scoped files."
            : "Detected \(findings.count) potential test coverage gap(s)."
        return (findings, true, summary)
    }

    static func runBugHotspotsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let history = gitHistoryFileCounts(workspacePath: workspacePath)
        guard !history.isEmpty else {
            return ([], false, "Git history unavailable for bug hotspot audit.")
        }

        let findings = scopeFiles.compactMap { file -> CodeReviewFinding? in
            guard let count = history[file], count >= 3 else { return nil }
            return makeFinding(
                severity: count >= 6 ? .warning : .suggestion,
                category: .regression,
                origin: .bugHunter,
                filePath: file,
                lineNumber: nil,
                message: "File changed frequently in the last 90 days and is a regression hotspot.",
                suggestedFix: "Review recent history carefully, add focused regression tests, and keep the patch narrow.",
                confidence: count >= 6 ? 0.78 : 0.62,
                evidence: "git log count over 90 days: \(count)",
                sourceTool: ReviewAuditToolName.bugHotspots,
                blocking: false
            )
        }

        let summary = findings.isEmpty
            ? "No recent regression hotspots detected in scoped files."
            : "Detected \(findings.count) hotspot file(s) based on recent git history."
        return (findings, true, summary)
    }
}
