import Foundation

extension UnifiedToolRuntime {
    func executeDebugTestCheck(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["scope"] ?? "related").lowercased()
        let rawPath = (call.args["path"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = (call.args["filter"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hypothesisId = (call.args["hypothesis_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let timeoutMs = Int(call.args["timeout_ms"] ?? "180000") ?? 180000
        let workspaceURL = context.workspaceContext.workspacePath
        let workspace = workspaceURL.path
        let ms = { Int(Date().timeIntervalSince(startDate) * 1000) }

        let descriptor: ProjectValidationDescriptor
        do {
            descriptor = try ValidationConfigLoader.load(workspaceRoot: workspaceURL)
        } catch {
            return ToolResult(ok: false, payload: [
                "title": "debug_test_check",
                "detail": "debug_test_check requires Solo Code validation config",
                "output": "Missing or invalid validation config at Config/validation/solocode-validation.json: \(error.localizedDescription)",
                "scope": scope,
                "error_code": "validation"
            ], durationMs: ms())
        }

        guard FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent(descriptor.workspace).path) else {
            return ToolResult(ok: false, payload: [
                "title": "debug_test_check",
                "detail": "Configured Xcode workspace not found",
                "output": "Workspace '\(descriptor.workspace)' does not exist under \(workspace).",
                "scope": scope,
                "error_code": "validation"
            ], durationMs: ms())
        }

        guard let xcodebuild = await resolvedDebugXcodebuildPath(cwd: workspace) else {
            return ToolResult(ok: false, payload: [
                "title": "debug_test_check",
                "detail": "xcodebuild is not available",
                "output": "Unable to locate a working xcodebuild executable for debug_test_check.",
                "scope": scope,
                "error_code": "validation"
            ], durationMs: ms())
        }

        let selectedFiles = selectedDebugTestFiles(
            scope: scope,
            rawPath: rawPath,
            hypothesisId: hypothesisId
        )

        let executions = debugTestExecutions(
            scope: scope,
            filter: filter,
            selectedFiles: selectedFiles,
            descriptor: descriptor
        )

        if scope == "failing" && executions.isEmpty {
            return ToolResult(ok: true, payload: [
                "title": "debug_test_check",
                "detail": "No previously failing tests to run [failing]",
                "output": "No previously failing Xcode tests recorded in this runtime session.",
                "scope": scope,
                "passed": "0",
                "failed": "0",
                "exit_code": "0",
                "overall_status": "skipped",
                "filter": ""
            ], durationMs: ms())
        }

        guard !executions.isEmpty else {
            return ToolResult(ok: false, payload: [
                "title": "debug_test_check",
                "detail": "Unable to resolve Xcode test scope",
                "output": "No Xcode test scheme or test group could be resolved for scope='\(scope)'.",
                "scope": scope,
                "error_code": "validation"
            ], durationMs: ms())
        }

        let sourcePackagesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("solocode-debug-test-check-source-packages", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourcePackagesDir, withIntermediateDirectories: true)

        await debugLogServer.log(
            severity: "info",
            source: "debug_test_check",
            message: "Running Xcode verification [scope=\(scope)] on \(executions.map(\.scheme).joined(separator: ", "))",
            category: "test"
        )

        var combinedOutputs: [String] = []
        var failingIdentifiers: [String] = []
        var passed = 0
        var failed = 0
        var lastExitCode = 0
        var executedCommands: [String] = []

        for execution in executions {
            let derivedDataPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("solocode-debug-test-check-\(execution.scheme.replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString)", isDirectory: true)

            var args = [
                xcodebuild,
                "test",
                "-workspace", descriptor.workspace,
                "-scheme", execution.scheme,
                "-destination", descriptor.destination,
                "-derivedDataPath", derivedDataPath.path,
                "-clonedSourcePackagesDirPath", sourcePackagesDir.path,
                "CODE_SIGNING_ALLOWED=NO",
            ]
            args.append(contentsOf: execution.onlyTesting.flatMap { ["-only-testing:\($0)"] })

            let (stdout, stderr, exitCode) = await shellExec(
                args: args,
                cwd: workspace,
                timeout: timeoutMs
            )
            lastExitCode = Int(exitCode)
            let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            combinedOutputs.append("### \(execution.scheme)\n\(combined)")
            executedCommands.append(([xcodebuild] + args.dropFirst()).joined(separator: " "))

            let parsed = parseXcodeTestOutput(combined)
            passed += parsed.passed
            failed += parsed.failed
            failingIdentifiers.append(contentsOf: parsed.failedIdentifiers)

            await debugLogServer.logTestOutput(combined, source: "debug_test_check/\(execution.scheme)")

            if exitCode != 0 {
                break
            }
        }

        let dedupedFailing = Array(Set(failingIdentifiers)).sorted()
        if lastExitCode == 0 {
            debugFailingTestFilters.removeAll()
        } else if !dedupedFailing.isEmpty {
            debugFailingTestFilters = dedupedFailing
        }

        let overallPassed = lastExitCode == 0
        let status = overallPassed ? "PASSED" : "FAILED"
        let schemeSummary = executions.map(\.scheme).joined(separator: ", ")
        await debugLogServer.log(
            severity: overallPassed ? "info" : "error",
            source: "debug_test_check",
            message: "Xcode tests \(status): \(passed) passed, \(failed) failed",
            detail: dedupedFailing.isEmpty ? nil : dedupedFailing.joined(separator: "\n"),
            category: "test"
        )

        var output = "## Xcode Test Results [\(scope)]\n\n"
        output += "- Status: \(overallPassed ? "PASSED ✓" : "FAILED ✗")\n"
        output += "- Schemes: \(schemeSummary)\n"
        output += "- Passed: \(passed)\n"
        output += "- Failed: \(failed)\n"
        if !filter.isEmpty {
            output += "- Filter: \(filter)\n"
        }
        if !selectedFiles.isEmpty {
            output += "- Files: \(selectedFiles.joined(separator: ", "))\n"
        }
        if !dedupedFailing.isEmpty {
            output += "\n### Failed Tests\n"
            output += dedupedFailing.map { "  - \($0)" }.joined(separator: "\n")
        }
        output += "\n\n### Commands\n"
        output += executedCommands.map { "  - \($0)" }.joined(separator: "\n")
        let combinedOutput = combinedOutputs.joined(separator: "\n\n")
        output += "\n\n### Output (truncated)\n```\n\(String(combinedOutput.suffix(4000)))\n```"

        return ToolResult(ok: overallPassed, payload: [
            "title": "debug_test_check",
            "detail": "\(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed [\(scope)]",
            "output": output,
            "scope": scope,
            "passed": "\(passed)",
            "failed": "\(failed)",
            "exit_code": "\(lastExitCode)",
            "overall_status": overallPassed ? "passed" : "failed",
            "filter": filter,
            "schemes": schemeSummary,
            "error_code": overallPassed ? "" : "test_failed"
        ], durationMs: ms())
    }

    private func selectedDebugTestFiles(
        scope: String,
        rawPath: String,
        hypothesisId: String
    ) -> [String] {
        switch scope {
        case "file":
            return rawPath.isEmpty ? [] : [rawPath]
        case "related":
            if !rawPath.isEmpty {
                return [rawPath]
            }
            if !hypothesisId.isEmpty,
               let hypothesis = resolvedDebugHypothesis(for: hypothesisId) {
                return hypothesis.relatedFiles
            }
            return []
        case "all", "failing", "integration":
            return []
        default:
            return rawPath.isEmpty ? [] : [rawPath]
        }
    }

    private func resolvedDebugHypothesis(for rawIdentifier: String) -> DebugHypothesis? {
        switch resolveHypothesisLookup(rawIdentifier) {
        case .resolved(let resolvedID):
            return debugHypotheses[resolvedID]
        case .ambiguous, .notFound:
            return nil
        }
    }

    private func debugTestExecutions(
        scope: String,
        filter: String,
        selectedFiles: [String],
        descriptor: ProjectValidationDescriptor
    ) -> [DebugTestExecution] {
        if scope == "integration" {
            return [DebugTestExecution(
                scheme: "Solo Code-IntegrationTests",
                onlyTesting: filter.isEmpty ? ["SoloCodeIntegrationTests"] : [filter]
            )]
        }

        if !filter.isEmpty {
            return debugExecutionsForExplicitFilter(filter)
        }

        if scope == "failing" {
            return debugExecutionsForStoredFailures()
        }

        if !selectedFiles.isEmpty {
            let groups = TargetedTestsSelector.select(files: selectedFiles, descriptor: descriptor)
            return groupedDebugTestExecutions(groups)
        }

        return [DebugTestExecution(scheme: descriptor.localScheme, onlyTesting: [])]
    }

    private func debugExecutionsForExplicitFilter(_ filter: String) -> [DebugTestExecution] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let filters = trimmed
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var grouped: [String: [String]] = [:]
        for testFilter in filters {
            grouped[schemeForTestIdentifier(testFilter), default: []].append(testFilter)
        }
        return grouped.keys.sorted().map { scheme in
            DebugTestExecution(scheme: scheme, onlyTesting: grouped[scheme] ?? [])
        }
    }

    private func debugExecutionsForStoredFailures() -> [DebugTestExecution] {
        guard !debugFailingTestFilters.isEmpty else { return [] }
        var grouped: [String: [String]] = [:]
        for testFilter in debugFailingTestFilters {
            grouped[schemeForTestIdentifier(testFilter), default: []].append(testFilter)
        }
        return grouped.keys.sorted().map { scheme in
            DebugTestExecution(scheme: scheme, onlyTesting: grouped[scheme] ?? [])
        }
    }

    private func groupedDebugTestExecutions(
        _ groups: [ValidationSelectedTestGroup]
    ) -> [DebugTestExecution] {
        var grouped: [String: Set<String>] = [:]
        for group in groups {
            let scheme = schemeForBundle(group.bundle)
            grouped[scheme, default: []].formUnion(group.onlyTesting)
        }
        return grouped.keys.sorted().map { scheme in
            DebugTestExecution(scheme: scheme, onlyTesting: Array(grouped[scheme] ?? []).sorted())
        }
    }

    private func schemeForBundle(_ bundle: String) -> String {
        switch bundle {
        case "CoderEngineTests":
            return "CoderEngineTests-Debug"
        case "SoloCodeIntegrationTests":
            return "Solo Code-IntegrationTests"
        default:
            return "Solo Code-Debug"
        }
    }

    private func schemeForTestIdentifier(_ identifier: String) -> String {
        if identifier.hasPrefix("CoderEngineTests/") {
            return "CoderEngineTests-Debug"
        }
        if identifier.hasPrefix("SoloCodeIntegrationTests/") {
            return "Solo Code-IntegrationTests"
        }
        return "Solo Code-Debug"
    }

    private func resolvedDebugXcodebuildPath(cwd: String) async -> String? {
        let envOverride = ProcessInfo.processInfo.environment["SOLOCODE_DEBUG_XCODEBUILD_PATH"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        return await resolveExecutablePath(
            candidates: [envOverride, "/usr/bin/xcodebuild"].compactMap { $0 },
            commandName: "xcodebuild",
            cwd: cwd
        )
    }

    private func parseXcodeTestOutput(_ output: String) -> (passed: Int, failed: Int, failedIdentifiers: [String]) {
        var passed = 0
        var failed = 0
        var failedIdentifiers: [String] = []

        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.contains("Test Case") && line.contains(" passed") {
                passed += 1
            } else if line.contains("Test Case") && line.contains(" failed") {
                failed += 1
                if let identifier = parseXcodeTestIdentifier(from: line) {
                    failedIdentifiers.append(identifier)
                }
            }
        }

        return (passed, failed, failedIdentifiers)
    }

    private func parseXcodeTestIdentifier(from line: String) -> String? {
        guard let range = line.range(of: "'-["),
              let closing = line[range.upperBound...].firstIndex(of: "]") else {
            return nil
        }

        let rawIdentifier = String(line[line.index(range.upperBound, offsetBy: 0)..<closing])
        let parts = rawIdentifier.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let suite = String(parts[0])
        let method = String(parts[1])
        let suiteParts = suite.split(separator: ".")
        guard suiteParts.count >= 2 else { return nil }
        let bundle = String(suiteParts[0])
        let testCase = suiteParts.dropFirst().joined(separator: ".")
        return "\(bundle)/\(testCase)/\(method)"
    }
}

private struct DebugTestExecution {
    let scheme: String
    let onlyTesting: [String]
}
