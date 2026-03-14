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
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
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

    static func runBugTestImpactAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let sourceFiles = scopeFiles.filter { !$0.lowercased().contains("test") }
        var findings: [CodeReviewFinding] = []
        for relativePath in sourceFiles {
            let absolutePath = workspacePath.appendingPathComponent(relativePath).path
            guard let indexed = SymbolExtractor.indexFile(
                absolutePath: absolutePath,
                relativePath: relativePath
            ) else { continue }
            let publicSymbols = indexed.symbols.filter { $0.accessLevel == .public || $0.accessLevel == .open }
            guard !publicSymbols.isEmpty else { continue }
            let testReferences = publicSymbols.filter { symbol in
                !findProjectFiles(named: "\(symbol.name)Tests.swift", workspacePath: workspacePath).isEmpty
            }
            if testReferences.isEmpty {
                findings.append(
                    makeFinding(
                        severity: .suggestion,
                        category: .tests,
                        origin: .bugHunter,
                        filePath: relativePath,
                        lineNumber: publicSymbols.first?.line,
                        message: "Simboli pubblici toccati senza segnali evidenti di test di impatto associati.",
                        suggestedFix: "Aggiungi o aggiorna test per i simboli pubblici modificati e i casi limite correlati.",
                        confidence: 0.66,
                        evidence: publicSymbols.map(\.name).joined(separator: ", "),
                        sourceTool: ReviewAuditToolName.bugTestImpact,
                        blocking: false
                    )
                )
            }
        }
        return (
            deduplicate(findings),
            !sourceFiles.isEmpty,
            findings.isEmpty ? "Nessun gap evidente di test impact sui simboli pubblici." : "Rilevati gap di test impact per simboli pubblici modificati.",
            [],
            ["signal_type": "test_derived", "verification_hint": "Conferma che i simboli pubblici modificati siano effettivamente coperti da test mirati", "promotion_gate": "strict_verified", "behavioral_impact": "regression_surface"]
        )
    }

    static func runBugDependencyDriftAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let manifests = ["Package.swift", "Package.resolved", "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "Podfile.lock", "go.mod", "Cargo.lock"]
        let changedManifests = scopeFiles.filter { manifests.contains(($0 as NSString).lastPathComponent) }
        guard !changedManifests.isEmpty else {
            return ([], !scopeFiles.isEmpty, "Nessun drift dependency rilevante nello scope.", [], ["signal_type": "pattern", "promotion_gate": "strict_verified"])
        }
        let finding = makeFinding(
            severity: .warning,
            category: .regression,
            origin: .bugHunter,
            filePath: changedManifests[0],
            lineNumber: nil,
            message: "Drift di dependency/lockfile rilevato senza verifica funzionale esplicita nello scope.",
            suggestedFix: "Verifica note di release, advisory, smoke test e regression test sulle aree colpite dalle dependency aggiornate.",
            confidence: 0.72,
            evidence: changedManifests.joined(separator: ", "),
            sourceTool: ReviewAuditToolName.bugDependencyDrift,
            blocking: false
        )
        return (
            [finding],
            true,
            "Rilevato drift di dependency o lockfile nello scope corrente.",
            [],
            ["signal_type": "pattern", "verification_hint": "Conferma se le dependency cambiate toccano runtime critici o flaky", "promotion_gate": "strict_verified"]
        )
    }

    static func runBugDiffSemanticsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let engine = SemanticDiffEngine()
        var changes: [SemanticChange] = []
        for file in scopeFiles {
            guard let diff = commandOutput(
                executable: "/usr/bin/git",
                arguments: ["diff", "--unified=0", "--", file],
                currentDirectoryURL: workspacePath
            ), diff.status == 0 else { continue }
            let lower = diff.output.lowercased()
            if lower.contains("+public func") || lower.contains("-public func") || lower.contains("+open func") || lower.contains("-open func") {
                changes.append(
                    engine.classifySignatureChange(
                        symbol: "public_api",
                        file: file,
                        oldSignature: "pre-change",
                        newSignature: "post-change",
                        isPublic: true
                    )
                )
            }
            if lower.contains("+import ") || lower.contains("-import ") {
                changes.append(engine.classifyImportChange(file: file, module: "dependency", added: true))
            }
        }

        guard !changes.isEmpty else {
            return ([], !scopeFiles.isEmpty, "Nessun semantic drift rilevante dal diff corrente.", [], ["signal_type": "semantic", "promotion_gate": "strict_verified"])
        }

        let report = engine.filterCosmeticChanges(
            from: engine.generateReport(taskId: "audit", patchId: "scope", changes: changes)
        )
        let findings = report.changes.map { change in
            makeFinding(
                severity: change.impact == .breakingChange ? .critical : .warning,
                category: .regression,
                origin: .bugHunter,
                filePath: change.file,
                lineNumber: nil,
                message: change.impact == .breakingChange
                    ? "Semantic diff indica breaking change nel contratto pubblico."
                    : "Semantic diff indica change non cosmetico da verificare.",
                suggestedFix: "Conferma backward compatibility, test di regressione e documentazione del change.",
                confidence: change.impact == .breakingChange ? 0.88 : 0.71,
                evidence: change.summary ?? "\(change.type.rawValue) in \(change.file)",
                sourceTool: ReviewAuditToolName.bugDiffSemantics,
                blocking: change.impact == .breakingChange
            )
        }
        return (
            deduplicate(findings),
            true,
            "Semantic diff ha rilevato \(report.summary.totalSemanticChanges) cambi non cosmetici.",
            [],
            [
                "signal_type": "semantic",
                "verification_hint": "Conferma backward compatibility e test di regressione per i semantic changes rilevati",
                "promotion_gate": "strict_verified",
                "behavioral_impact": report.hasBreakingChanges ? "breaking_change" : "behavior_change",
            ]
        )
    }
}
