import Foundation

extension UnifiedToolRuntime {
    func executeDebugContext(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePath.path
        let workspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let preferredRoot = context.workspaceContext.activeRootPath
        var sections: [String] = []

        let scopeRaw = call.args["scope"] ?? "full"
        let scopes = Set(scopeRaw.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let isFull = scopes.contains("full")
        let includeContent = call.args["include_file_content"]?.lowercased() == "true"
        let maxDepth = max(1, min(8, Int(call.args["max_depth"] ?? "3") ?? 3))

        // 1. Git status + diff + log
        if isFull || scopes.contains("git") {
            let (gitStatus, _, gitExit) = await shellExec(
                args: ["/usr/bin/git", "status", "--short", "--branch"],
                cwd: workspace, timeout: 5_000
            )
            if gitExit == 0 {
                sections.append("## Git Status\n\(gitStatus)")
            }

            let (gitDiff, _, _) = await shellExec(
                args: ["/usr/bin/git", "diff", "--stat", "HEAD"],
                cwd: workspace, timeout: 5_000
            )
            if !gitDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Git Diff (stat)\n\(gitDiff)")
            }

            let (gitLog, _, _) = await shellExec(
                args: ["/usr/bin/git", "log", "--oneline", "-5"],
                cwd: workspace, timeout: 5_000
            )
            if !gitLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Recent Commits\n\(gitLog)")
            }
        }

        // 2. Build errors
        if isFull || scopes.contains("build") {
            let (buildOut, buildErr, buildExit) = await shellExec(
                args: ["/usr/bin/swift", "build", "--skip-update"],
                cwd: workspace, timeout: 30_000
            )
            let buildOutput = (buildOut + "\n" + buildErr).trimmingCharacters(in: .whitespacesAndNewlines)
            if buildExit != 0 && !buildOutput.isEmpty {
                let truncatedBuild = String(buildOutput.prefix(3000))
                sections.append("## Build Errors (exit \(buildExit))\n```\n\(truncatedBuild)\n```")
            } else {
                sections.append("## Build Status\nClean build (exit 0)")
            }
        }

        // 3. Linter diagnostics
        if isFull || scopes.contains("lints") {
            let lintStartDate = Date()
            let lintCall = ToolCall(
                id: UUID().uuidString, name: "read_lints",
                args: ["severity": "error", "limit": "20"],
                sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope
            )
            let lintResult = await executeReadLints(call: lintCall, context: context, startDate: lintStartDate)
            if lintResult.ok {
                let errorCount = lintResult.payload["error_count"] ?? "0"
                let warningCount = lintResult.payload["warning_count"] ?? "0"
                let linter = lintResult.payload["linter"] ?? "unknown"
                var lintSection = "## Linter Diagnostics (\(linter))\nErrors: \(errorCount), Warnings: \(warningCount)"
                if let output = lintResult.payload["output"], !output.isEmpty, errorCount != "0" {
                    lintSection += "\n```\n\(String(output.prefix(2000)))\n```"

                    if includeContent {
                        let errorFiles = parseErrorFiles(from: output)
                        for (filePath, lineNum) in errorFiles.prefix(5) {
                            guard let fullPath = resolvePath(
                                filePath,
                                workspacePaths: workspacePaths,
                                preferredRoot: preferredRoot,
                                sandboxMode: context.policy.sandboxMode
                            ) else {
                                continue
                            }
                            let owningRoot = workspacePaths.first(where: { root in
                                let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
                                let normalizedPath = URL(fileURLWithPath: fullPath).standardizedFileURL.path
                                return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
                            }) ?? workspace
                            let relativePath = fullPath.hasPrefix(owningRoot + "/")
                                ? String(fullPath.dropFirst(owningRoot.count + 1))
                                : fullPath
                            let pathDepth = max(1, relativePath.split(separator: "/").count)
                            guard pathDepth <= maxDepth else { continue }
                            if let fileContent = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                                let allLines = fileContent.components(separatedBy: "\n")
                                let start = max(0, lineNum - 10)
                                let end = min(allLines.count, lineNum + 10)
                                let snippet = allLines[start..<end].enumerated().map { "\(start + $0.offset + 1)| \($0.element)" }.joined(separator: "\n")
                                lintSection += "\n\n### \(filePath):\(lineNum)\n```\n\(snippet)\n```"
                            }
                        }
                    }
                }
                sections.append(lintSection)
            }
        }

        // 4. Environment info
        if isFull || scopes.contains("env") {
            var envLines: [String] = []
            let (swiftVer, _, _) = await shellExec(
                args: ["/usr/bin/swift", "--version"],
                cwd: workspace, timeout: 5_000
            )
            if !swiftVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("Swift: \(swiftVer.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? swiftVer)")
            }

            let (xcodeVer, _, _) = await shellExec(
                args: ["/usr/bin/xcodebuild", "-version"],
                cwd: workspace, timeout: 5_000
            )
            if !xcodeVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("Xcode: \(xcodeVer.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: ", "))")
            }

            let (sdkPath, _, _) = await shellExec(
                args: ["/usr/bin/xcrun", "--show-sdk-path"],
                cwd: workspace, timeout: 5_000
            )
            if !sdkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("SDK: \(sdkPath.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            envLines.append("Platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            envLines.append("CPU cores: \(ProcessInfo.processInfo.activeProcessorCount)")

            sections.append("## Environment\n\(envLines.joined(separator: "\n"))")
        }

        // 5. Test listing
        if isFull || scopes.contains("tests") {
            let (testListOut, testListErr, testExit) = await shellExec(
                args: ["/usr/bin/swift", "test", "list"],
                cwd: workspace, timeout: 15_000
            )
            let trimmed = (testListOut + "\n" + testListErr).trimmingCharacters(in: .whitespacesAndNewlines)
            if testExit == 0 && !trimmed.isEmpty {
                let testLines = trimmed.components(separatedBy: "\n")
                sections.append("## Tests (\(testLines.count) test cases)\n\(testLines.prefix(30).joined(separator: "\n"))\(testLines.count > 30 ? "\n... +\(testLines.count - 30) more" : "")")
            } else if !trimmed.isEmpty {
                sections.append("## Tests\n```\n\(String(trimmed.prefix(1500)))\n```")
            }
        }

        // 6. Recent crash reports
        if isFull || scopes.contains("crashes") {
            let crashDir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
            let fm = FileManager.default
            if fm.fileExists(atPath: crashDir) {
                let (crashFiles, _, _) = await shellExec(
                    args: ["/bin/ls", "-t", crashDir],
                    cwd: workspace, timeout: 3_000
                )
                let files = crashFiles.components(separatedBy: "\n").filter { !$0.isEmpty }
                let recentCrashes = files.prefix(5)
                if !recentCrashes.isEmpty {
                    var crashSection = "## Recent Crash Reports (\(files.count) total, showing \(recentCrashes.count))\n"
                    for crashFile in recentCrashes {
                        crashSection += "- \(crashFile)\n"
                    }
                    sections.append(crashSection)
                }
            }
        }

        // 7. Dependencies (Package.resolved)
        if isFull || scopes.contains("build") {
            let resolvedPath = workspace + "/Package.resolved"
            if FileManager.default.fileExists(atPath: resolvedPath) {
                if let resolvedContent = try? String(contentsOfFile: resolvedPath, encoding: .utf8) {
                    let truncated = String(resolvedContent.prefix(2000))
                    sections.append("## Dependencies (Package.resolved)\n```json\n\(truncated)\n```")
                }
            }
        }

        // 8. Open files
        let openFiles = context.workspaceContext.openFiles
        if !openFiles.isEmpty {
            var fileSection = "## Open Files (\(openFiles.count))\n"
            for file in openFiles {
                let lineCount = file.content.components(separatedBy: "\n").count
                fileSection += "- \(file.path) (\(lineCount) lines)\n"
            }
            sections.append(fileSection)
        }

        // 9. Active file and selection
        if let activeFile = context.workspaceContext.activeFilePath {
            sections.append("## Active File\n\(activeFile)")
        }
        if let selection = context.workspaceContext.activeSelection, !selection.isEmpty {
            let preview = selection.count > 500 ? String(selection.prefix(500)) + "..." : selection
            sections.append("## Active Selection\n```\n\(preview)\n```")
        }

        // 10. Debug log summary
        let debugSnapshot = await debugLogServer.query(limit: 5)
        if debugSnapshot.totalCount > 0 {
            let summary = await debugLogServer.sessionSummary()
            if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Debug Log Summary\n\(summary)")
            }
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let fullContext = sections.joined(separator: "\n\n")

        return ToolResult(ok: true, payload: [
            "title": "debug_context",
            "detail": "Debug context gathered: \(sections.count) sections [\(scopes.joined(separator: ","))]",
            "output": truncate(fullContext, maxBytes: context.policy.maxBashOutputBytes),
            "sections": "\(sections.count)",
            "scopes": scopeRaw
        ], durationMs: ms)
    }

    func parseErrorFiles(from lintOutput: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        let lines = lintOutput.components(separatedBy: "\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 3)
            if parts.count >= 3,
               let lineNum = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let filePath = String(parts[0])
                if !result.contains(where: { $0.0 == filePath && $0.1 == lineNum }) {
                    result.append((filePath, lineNum))
                }
            }
        }
        return result
    }

}
