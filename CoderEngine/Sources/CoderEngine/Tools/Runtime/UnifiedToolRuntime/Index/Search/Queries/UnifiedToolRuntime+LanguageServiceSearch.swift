import Foundation

extension UnifiedToolRuntime {
    func executeIndexToolViaLanguageServiceIfAvailable(
        name: String,
        args: [String: String],
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult? {
        guard let languageService else { return nil }
        switch name {
        case "find_symbol":
            return await executeLanguageServiceFindSymbol(
                languageService: languageService,
                args: args,
                context: context,
                startDate: startDate
            )
        case "find_references":
            return await executeLanguageServiceFindReferences(
                languageService: languageService,
                args: args,
                context: context,
                startDate: startDate
            )
        default:
            return nil
        }
    }

    func resolveLanguageLocationPath(
        _ rawPath: String,
        workspacePaths: [String],
        primaryWorkspace: String
    ) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if (trimmed as NSString).isAbsolutePath {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        }
        if FileManager.default.fileExists(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed).standardizedFileURL.path
        }
        for workspace in workspacePaths {
            let candidate = URL(fileURLWithPath: workspace)
                .appendingPathComponent(trimmed)
                .standardizedFileURL
                .path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
            let parentCandidate = URL(fileURLWithPath: workspace)
                .deletingLastPathComponent()
                .appendingPathComponent(trimmed)
                .standardizedFileURL
                .path
            if FileManager.default.fileExists(atPath: parentCandidate) {
                return parentCandidate
            }
        }
        return URL(fileURLWithPath: primaryWorkspace)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
            .path
    }

    private func executeLanguageServiceFindSymbol(
        languageService: any RuntimeLanguageService,
        args: [String: String],
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult? {
        let query = (args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        do {
            let fileHint = args["fileHint"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let definitions = try await languageService.goToDefinition(
                symbol: query,
                fileHint: fileHint?.isEmpty == true ? nil : fileHint
            )
            guard !definitions.isEmpty else { return nil }
            let allWorkspacePaths = preferredWorkspacePaths(for: context).map(\.path)
            let primaryWorkspace = allWorkspacePaths.first ?? context.workspaceContext.workspacePath.path
            var lines: [String] = []
            lines.append("Found \(definitions.count) definition(s) for '\(query)':")
            lines.append("")
            for definition in definitions {
                let absolutePath = resolveLanguageLocationPath(
                    definition.filePath,
                    workspacePaths: allWorkspacePaths,
                    primaryWorkspace: primaryWorkspace
                )
                let displayPath = makeDisplayPath(
                    absolutePath: absolutePath,
                    workspacePaths: allWorkspacePaths
                )
                let lineColumn = definition.column.map { "\(definition.line):\($0)" } ?? "\(definition.line)"
                lines.append("  \(displayPath):\(lineColumn) [\(definition.source.rawValue)]")
            }
            return success([
                "title": "find_symbol: \(query)",
                "detail": "\(definitions.count) definition(s) [language_service]",
                "output": lines.joined(separator: "\n")
            ], startDate: startDate)
        } catch {
            return nil
        }
    }

    private func executeLanguageServiceFindReferences(
        languageService: any RuntimeLanguageService,
        args: [String: String],
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult? {
        let query = (args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let limit = max(1, Int((args["limit"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 100)

        do {
            let references = try await languageService.findReferences(symbol: query, limit: limit)
            guard !references.isEmpty else { return nil }
            let allWorkspacePaths = preferredWorkspacePaths(for: context).map(\.path)
            let primaryWorkspace = allWorkspacePaths.first ?? context.workspaceContext.workspacePath.path
            var lines: [String] = []
            lines.append("Found \(references.count) reference(s) for '\(query)':")
            lines.append("")
            for reference in references.prefix(100) {
                let absolutePath = resolveLanguageLocationPath(
                    reference.filePath,
                    workspacePaths: allWorkspacePaths,
                    primaryWorkspace: primaryWorkspace
                )
                let displayPath = makeDisplayPath(
                    absolutePath: absolutePath,
                    workspacePaths: allWorkspacePaths
                )
                lines.append("  \(displayPath):\(reference.line) — \(reference.symbolName)")
            }
            if references.count > 100 {
                lines.append("  ... and \(references.count - 100) more")
            }
            return success([
                "title": "find_references: \(query)",
                "detail": "\(references.count) references [language_service]",
                "output": lines.joined(separator: "\n")
            ], startDate: startDate)
        } catch {
            return nil
        }
    }

    private func makeDisplayPath(absolutePath: String, workspacePaths: [String]) -> String {
        for workspacePath in workspacePaths {
            let prefix = workspacePath.hasSuffix("/") ? workspacePath : workspacePath + "/"
            if absolutePath.hasPrefix(prefix) {
                return String(absolutePath.dropFirst(prefix.count))
            }
        }
        return absolutePath
    }
}
