import Foundation

extension UnifiedToolRuntime {
    func executeDebugTestCheck(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["scope"] ?? "related").lowercased()
        let rawPath = call.args["path"] ?? ""
        let filter = call.args["filter"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let timeoutMs = Int(call.args["timeout_ms"] ?? "60000") ?? 60000
        let workspace = context.workspaceContext.workspacePath.path
        let packageSwift = (workspace as NSString).appendingPathComponent("Package.swift")
        if !FileManager.default.fileExists(atPath: packageSwift) {
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: false, payload: [
                "title": "debug_test_check",
                "detail": "debug_test_check currently supports Swift Package projects only",
                "output": "No Package.swift found in workspace. Use language-specific test tooling for non-Swift projects.",
                "scope": scope,
                "error_code": "validation"
            ], durationMs: ms)
        }

        var testArgs: [String] = ["/usr/bin/swift", "test"]

        // Determine test filter based on scope
        var testFilter = filter
        if testFilter.isEmpty {
            switch scope {
            case "file":
                if !rawPath.isEmpty {
                    let fileName = (rawPath as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
                    testFilter = fileName
                }
            case "related":
                if !rawPath.isEmpty {
                    let fileName = (rawPath as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
                    testFilter = fileName
                } else if !hypothesisId.isEmpty, let hyp = debugHypotheses[hypothesisId] {
                    let fileNames = hyp.relatedFiles.compactMap { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "") }
                    if let first = fileNames.first { testFilter = first }
                }
            case "failing":
                if let firstFailing = debugFailingTestFilters.first {
                    testFilter = firstFailing
                } else {
                    let ms = Int(Date().timeIntervalSince(startDate) * 1000)
                    return ToolResult(ok: true, payload: [
                        "title": "debug_test_check",
                        "detail": "No previously failing tests to run [failing]",
                        "output": "No previously failing tests recorded in this runtime session.",
                        "scope": scope,
                        "passed": "0",
                        "failed": "0",
                        "exit_code": "0",
                        "overall_status": "skipped",
                        "filter": ""
                    ], durationMs: ms)
                }
            case "all":
                break
            default:
                break
            }
        }

        if !testFilter.isEmpty {
            testArgs += ["--filter", testFilter]
        }

        await debugLogServer.log(
            severity: "info",
            source: "debug_test_check",
            message: "Running tests [scope=\(scope)]\(testFilter.isEmpty ? "" : " filter=\(testFilter)")",
            category: "test"
        )

        let (stdout, stderr, exitCode) = await shellExec(
            args: testArgs,
            cwd: workspace,
            timeout: timeoutMs
        )

        let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse test results
        var passed = 0
        var failed = 0
        var failedTests: [String] = []
        let resultLines = combined.components(separatedBy: "\n")
        for line in resultLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("passed") && trimmed.contains("Test Case") {
                passed += 1
            } else if trimmed.contains("failed") && trimmed.contains("Test Case") {
                failed += 1
                failedTests.append(trimmed)
            }
        }

        // Check for overall pass/fail from Swift test summary
        let overallPassed = exitCode == 0

        var dedupedFailingFilters: [String] = []
        var seenFailingFilters: Set<String> = []
        for failedLine in failedTests {
            if let parsed = parseSwiftTestFilter(from: failedLine), seenFailingFilters.insert(parsed).inserted {
                dedupedFailingFilters.append(parsed)
            }
        }
        if overallPassed {
            debugFailingTestFilters.removeAll()
        } else if !dedupedFailingFilters.isEmpty {
            debugFailingTestFilters = dedupedFailingFilters
        }

        await debugLogServer.log(
            severity: overallPassed ? "info" : "error",
            source: "debug_test_check",
            message: "Tests \(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed",
            detail: failedTests.isEmpty ? nil : failedTests.joined(separator: "\n"),
            category: "test"
        )

        var output = "## Test Results [\(scope)]\n\n"
        output += "- Status: \(overallPassed ? "PASSED ✓" : "FAILED ✗")\n"
        output += "- Passed: \(passed)\n"
        output += "- Failed: \(failed)\n"
        if !testFilter.isEmpty { output += "- Filter: \(testFilter)\n" }
        if !failedTests.isEmpty {
            output += "\n### Failed Tests\n" + failedTests.map { "  - \($0)" }.joined(separator: "\n")
        }
        output += "\n\n### Output (truncated)\n```\n\(String(combined.suffix(2000)))\n```"

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: overallPassed, payload: [
            "title": "debug_test_check",
            "detail": "\(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed [\(scope)]",
            "output": output,
            "scope": scope,
            "passed": "\(passed)",
            "failed": "\(failed)",
            "exit_code": "\(exitCode)",
            "overall_status": overallPassed ? "passed" : "failed",
            "filter": testFilter,
            "error_code": overallPassed ? "" : "test_failed"
        ], durationMs: ms)
    }

    func parseSwiftTestFilter(from line: String) -> String? {
        guard let start = line.range(of: "'"),
              let end = line.range(of: "'", range: start.upperBound..<line.endIndex)
        else {
            return nil
        }
        let qualified = String(line[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qualified.isEmpty else { return nil }
        if let bracketStart = qualified.lastIndex(of: "["), let bracketEnd = qualified.lastIndex(of: "]"), bracketStart < bracketEnd {
            let inside = qualified[qualified.index(after: bracketStart)..<bracketEnd]
            return String(inside)
        }
        return qualified
    }
}
