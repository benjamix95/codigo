import Foundation

extension UnifiedToolRuntime {

    // MARK: - New Tool: diagnostics

    func executeDiagnostics(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let manager = (call.args["manager"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Auto-detect project type if not specified
        let buildCommand: String
        let projectType: String
        if !manager.isEmpty {
            switch manager {
            case "swift": buildCommand = "swift build 2>&1"; projectType = "Swift"
            case "npm": buildCommand = "npm run build 2>&1 || true"; projectType = "Node/npm"
            case "cargo": buildCommand = "cargo check 2>&1"; projectType = "Rust/Cargo"
            case "go": buildCommand = "go build ./... 2>&1"; projectType = "Go"
            default: buildCommand = "swift build 2>&1"; projectType = manager
            }
        } else {
            // Auto-detect
            let wsPath = context.workspaceContext.workspacePath.path
            if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("Package.swift")) {
                buildCommand = "swift build 2>&1"
                projectType = "Swift"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("package.json")) {
                buildCommand = "npm run build 2>&1 || true"
                projectType = "Node/npm"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("Cargo.toml")) {
                buildCommand = "cargo check 2>&1"
                projectType = "Rust/Cargo"
            } else if FileManager.default.fileExists(atPath: (wsPath as NSString).appendingPathComponent("go.mod")) {
                buildCommand = "go build ./... 2>&1"
                projectType = "Go"
            } else {
                buildCommand = "swift build 2>&1"
                projectType = "Swift (default)"
            }
        }

        let buildResult = await runBash(
            command: buildCommand,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Diagnostics",
            timeoutMs: max(context.policy.timeoutMs, 120_000),
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )

        let rawOutput = buildResult.payload["output"] ?? ""

        // Parse diagnostics from output
        var errors: [(file: String, line: String, col: String, severity: String, message: String)] = []
        let diagnosticPattern = try? NSRegularExpression(pattern: #"^(.+?):(\d+):(\d+):\s*(error|warning|note):\s*(.+)$"#, options: .anchorsMatchLines)

        if let regex = diagnosticPattern {
            let matches = regex.matches(in: rawOutput, range: NSRange(rawOutput.startIndex..., in: rawOutput))
            for match in matches.prefix(100) {
                guard match.numberOfRanges >= 6 else { continue }
                func extract(_ i: Int) -> String {
                    guard let r = Range(match.range(at: i), in: rawOutput) else { return "" }
                    return String(rawOutput[r])
                }
                errors.append((file: extract(1), line: extract(2), col: extract(3), severity: extract(4), message: extract(5)))
            }
        }

        let errorCount = errors.filter { $0.severity == "error" }.count
        let warningCount = errors.filter { $0.severity == "warning" }.count

        var output = "Project: \(projectType)\n"
        output += "Status: \(buildResult.ok ? "BUILD SUCCESS" : "BUILD FAILED")\n"
        output += "Errors: \(errorCount), Warnings: \(warningCount)\n\n"

        if !errors.isEmpty {
            for diag in errors.prefix(50) {
                let icon = diag.severity == "error" ? "ERROR" : diag.severity == "warning" ? "WARN" : "NOTE"
                output += "[\(icon)] \(diag.file):\(diag.line):\(diag.col) \(diag.message)\n"
            }
            if errors.count > 50 {
                output += "... and \(errors.count - 50) more diagnostics\n"
            }
        } else if !buildResult.ok {
            output += rawOutput
        }

        return ToolResult(
            ok: true,
            payload: [
                "title": "Diagnostics (\(projectType))",
                "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                "detail": buildResult.ok ? "Build OK" : "\(errorCount) errors, \(warningCount) warnings"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

    func executeRunSingleTest(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let testName = call.args["test"] ?? call.args["name"] ?? call.args["filter"] ?? ""
        let target = call.args["target"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !testName.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "test name/filter is required"], durationMs: 0)
        }

        // Detect project type and build command
        let fm = FileManager.default
        var cmd: [String]
        if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("Package.swift")) {
            cmd = ["/usr/bin/swift", "test", "--filter", testName]
            if !target.isEmpty { cmd += ["--target", target] }
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("package.json")) {
            cmd = ["/usr/bin/env", "npx", "jest", "--testPathPattern", testName, "--no-coverage"]
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("Cargo.toml")) {
            cmd = ["/usr/bin/env", "cargo", "test", testName, "--", "--nocapture"]
        } else if fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("go.mod")) {
            cmd = ["/usr/bin/env", "go", "test", "-run", testName, "-v", "./..."]
        } else {
            cmd = ["/usr/bin/swift", "test", "--filter", testName]
        }

        let (output, stderr, exitCode) = await shellExec(args: cmd, cwd: workspace, timeout: 120_000)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let combined = (output + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        // Also log to debug server
        await debugLogServer.logTestOutput(combined, source: "run_single_test:\(testName)")

        if exitCode == 0 {
            return ToolResult(ok: true, payload: [
                "title": "run_single_test",
                "detail": "Test '\(testName)' passed",
                "output": String(combined.suffix(8000))
            ], durationMs: ms)
        } else {
            return ToolResult(ok: false, payload: [
                "title": "run_single_test",
                "detail": "Test '\(testName)' failed (exit \(exitCode))",
                "output": String(combined.suffix(8000))
            ], durationMs: ms)
        }
    }

    // MARK: - Debug Tools
}
