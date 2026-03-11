import XCTest
@testable import CoderEngine

final class ValidationPerformanceTests: XCTestCase {
    func testSelectorPerformanceOnLargeFileList() {
        let descriptor = ProjectValidationDescriptor(
            version: 1,
            workspace: "Solo Code.xcworkspace",
            localScheme: "Solo Code-Debug",
            releaseScheme: "Solo Code-Release",
            destination: "platform=macOS",
            testPlan: nil,
            codeFileGlobs: ["Engine/**/*.swift"],
            excludedCodePaths: [],
            securitySensitivePrefixes: [],
            testGroups: [
                ValidationTestGroup(id: "engine-pipeline", bundle: "CoderEngineTests", pathPrefixes: ["Engine/CoderEngine/Sources/Pipeline/"], onlyTesting: ["CoderEngineTests/Pipeline"]),
            ]
        )
        let files = (0..<1000).map { "Engine/CoderEngine/Sources/Pipeline/File\($0).swift" }

        measure {
            _ = TargetedTestsSelector.select(files: files, descriptor: descriptor)
        }
    }

    func testReviewCoreBridgeSmokeBenchmark() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-core-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("Service.swift")
        try """
        let input = request.query["cmd"]
        runProcess(input, shell: true)
        fatalError("boom")
        """.write(to: file, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            id: "bench-candidate",
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "Service.swift",
            lineNumber: 3,
            message: "Potential nil access",
            evidence: "fatalError()",
            confidence: 0.9
        )
        let findings = (0..<120).map { index in
            VerifiedFinding(
                id: "finding-\(index)",
                domain: .bug,
                title: "Duplicate terminal event \(index % 2)",
                summary: "Late retry emits duplicate terminal event",
                category: "correctness",
                severity: .medium,
                confidence: 0.85,
                status: .candidate,
                filePath: "Sources/Runtime/Flow.swift",
                lineStart: 40 + (index % 3),
                originEntryPoint: .mainChat,
                findingFingerprint: "fingerprint-\(index % 2)"
            )
        }

        let verifySamples = measureSamples(iterations: 20) {
            _ = ReviewCandidateVerificationService.verify(
                candidate: candidate,
                workspacePath: root,
                scopeFiles: ["Service.swift"]
            )
        }
        let syncSamples = measureSamples(iterations: 20) {
            _ = VerifiedFindingsSessionSyncService.syncWithRustForBenchmark(findings: findings, traceLog: ["a", "b"])
        }
        let auditSamples = measureSamples(iterations: 10) {
            _ = CodeReviewAuditService.runTool(
                named: ReviewAuditToolName.securityDataflow,
                scopeFiles: ["Service.swift"],
                workspacePath: root
            )
        }

        XCTAssertFalse(verifySamples.isEmpty)
        XCTAssertFalse(syncSamples.isEmpty)
        XCTAssertFalse(auditSamples.isEmpty)

        if let outputPath = ProcessInfo.processInfo.environment["SOLOCODE_REVIEW_ENGINE_BENCHMARK_OUTPUT"] {
            let payload: [String: Any] = [
                "verify_candidate_p95_ms": percentile95(sync: verifySamples),
                "verified_sync_p95_ms": percentile95(sync: syncSamples),
                "audit_suite_duration_ms": percentile95(sync: auditSamples),
                "rust_review_core_loaded": ReviewCoreBridge.loadedVersion() != nil,
            ]
            if let summary = String(
                data: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                encoding: .utf8
            ) {
                print("REVIEW_ENGINE_BENCHMARK \(summary)")
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: outputPath))
        } else {
            let payload: [String: Any] = [
                "verify_candidate_p95_ms": percentile95(sync: verifySamples),
                "verified_sync_p95_ms": percentile95(sync: syncSamples),
                "audit_suite_duration_ms": percentile95(sync: auditSamples),
                "rust_review_core_loaded": ReviewCoreBridge.loadedVersion() != nil,
            ]
            if let summary = String(
                data: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                encoding: .utf8
            ) {
                print("REVIEW_ENGINE_BENCHMARK \(summary)")
            }
        }
    }

    private func measureSamples(iterations: Int, _ work: () -> Void) -> [Double] {
        (0..<iterations).map { _ in
            let started = CFAbsoluteTimeGetCurrent()
            work()
            return (CFAbsoluteTimeGetCurrent() - started) * 1000
        }
    }

    private func percentile95(sync samples: [Double]) -> Double {
        let sorted = samples.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        return sorted[index]
    }
}
