import Foundation

extension UnifiedToolRuntime {
    func executeReadLints(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePath.path
        let rawPath = call.args["path"] ?? ""
        let severity = call.args["severity"] ?? "all"  // all, error, warning
        let maxCount = Int(call.args["limit"] ?? "50") ?? 50

        // Strategy: Detect project type and use the fastest lint-only command
        var lintOutput = ""
        var lintErrors: [String] = []
        var toolUsed = ""

        // Check for Swift project
        let packageSwift = (workspace as NSString).appendingPathComponent("Package.swift")
        let xcodeproj = try? FileManager.default.contentsOfDirectory(atPath: workspace).first { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }

        if FileManager.default.fileExists(atPath: packageSwift) || xcodeproj != nil {
            // Swift: use `swift build --skip-link` for fast compile-only check, or swiftc -typecheck for single file
            toolUsed = "swift"
            if !rawPath.isEmpty {
                let filePath = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
                let (out, err, _) = await shellExec(
                    args: ["/usr/bin/xcrun", "swiftc", "-typecheck", filePath],
                    cwd: workspace, timeout: 30_000
                )
                lintOutput = out
                if !err.isEmpty { lintErrors.append(err) }
            } else {
                let (out, err, _) = await shellExec(
                    args: ["/usr/bin/swift", "build", "--skip-link"],
                    cwd: workspace, timeout: 60_000
                )
                lintOutput = out + "\n" + err
            }
        }

        // Check for Node/TS project
        let packageJson = (workspace as NSString).appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: packageJson) && toolUsed.isEmpty {
            // Try eslint first, then tsc --noEmit
            let eslintPath = (workspace as NSString).appendingPathComponent("node_modules/.bin/eslint")
            if FileManager.default.fileExists(atPath: eslintPath) {
                toolUsed = "eslint"
                var args = [eslintPath, "--format", "compact", "--no-color"]
                if !rawPath.isEmpty { args.append(rawPath) } else { args.append(".") }
                let (out, err, _) = await shellExec(args: args, cwd: workspace, timeout: 30_000)
                lintOutput = out
                if !err.isEmpty { lintErrors.append(err) }
            } else {
                // tsc --noEmit
                let tscPath = (workspace as NSString).appendingPathComponent("node_modules/.bin/tsc")
                if FileManager.default.fileExists(atPath: tscPath) {
                    toolUsed = "tsc"
                    let (out, err, _) = await shellExec(
                        args: [tscPath, "--noEmit", "--pretty", "false"],
                        cwd: workspace, timeout: 30_000
                    )
                    lintOutput = out
                    if !err.isEmpty { lintErrors.append(err) }
                }
            }
        }

        // Check for Cargo (Rust)
        let cargoToml = (workspace as NSString).appendingPathComponent("Cargo.toml")
        if FileManager.default.fileExists(atPath: cargoToml) && toolUsed.isEmpty {
            toolUsed = "cargo"
            let (out, err, _) = await shellExec(
                args: ["/usr/bin/env", "cargo", "check", "--message-format=short"],
                cwd: workspace, timeout: 60_000
            )
            lintOutput = out + "\n" + err
        }

        // Check for Go
        let goMod = (workspace as NSString).appendingPathComponent("go.mod")
        if FileManager.default.fileExists(atPath: goMod) && toolUsed.isEmpty {
            toolUsed = "go"
            let target = rawPath.isEmpty ? "./..." : rawPath
            let (out, err, _) = await shellExec(
                args: ["/usr/bin/env", "go", "vet", target],
                cwd: workspace, timeout: 30_000
            )
            lintOutput = out + "\n" + err
        }

        // Fallback: no recognized project type
        if toolUsed.isEmpty {
            return failure(
                "No recognized linter found. Supported: Swift (Package.swift/xcodeproj), Node (eslint/tsc), Cargo, Go.",
                errorCode: "validation", startDate: startDate
            )
        }

        // Parse and filter diagnostics
        let allLines = lintOutput.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let filtered: [String]
        switch severity {
        case "error":
            filtered = allLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("error") || lower.contains("fatal")
            }
        case "warning":
            filtered = allLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("warning") || lower.contains("warn")
            }
        default:
            filtered = allLines
        }

        let limited = Array(filtered.prefix(maxCount))
        let errorCount = limited.filter { $0.lowercased().contains("error") }.count
        let warningCount = limited.filter { $0.lowercased().contains("warning") }.count

        let summary = "\(errorCount) errors, \(warningCount) warnings (via \(toolUsed))"

        return success([
            "title": "read_lints",
            "linter": toolUsed,
            "error_count": "\(errorCount)",
            "warning_count": "\(warningCount)",
            "detail": summary,
            "output": truncate(limited.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
            "total_diagnostics": "\(filtered.count)"
        ], startDate: startDate)
    }
}
