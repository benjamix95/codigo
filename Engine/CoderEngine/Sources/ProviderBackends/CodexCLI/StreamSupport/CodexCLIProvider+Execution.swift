import Foundation

extension CodexCLIProvider {
    static func streamInvocation(
        executable: String,
        arguments: [String]
    ) -> (executable: String, arguments: [String]) {
        // Avoid PTY wrapping via `/usr/bin/script`: it may inject control bytes
        // (e.g. ^D/backspaces) and occasionally exit with code 1 and empty stderr
        // during delegated swarm follow-up runs. `codex exec --json` already
        // streams newline-delimited events reliably on a regular pipe.
        (executable, arguments)
    }

    static func buildExecArguments(
        fullPrompt: String,
        imageURLs: [URL]?,
        sandboxMode: CodexSandboxMode,
        yoloMode: Bool,
        askForApproval: String,
        workspacePath: String,
        modelOverride: String?,
        modelReasoningEffort: String?,
        modelProviderOverride: String?,
        fastMode: Bool,
        preferOpenAIResponsesWireAPI: Bool
    ) -> [String] {
        var args: [String] = []
        if let urls = imageURLs, !urls.isEmpty {
            let paths = urls.map { $0.path }.joined(separator: ",")
            args += ["exec", "--image", paths]
        } else {
            args += ["exec"]
        }
        args += ["--json"]
        // Codex CLI does not accept --full-auto together with --yolo/--dangerously-bypass-approvals-and-sandbox.
        if !yoloMode {
            args += ["--full-auto"]
        }
        args += [
            "--sandbox", sandboxMode.rawValue,
            "--cd", workspacePath,
            fullPrompt,
        ]

        func insertPromptScopedFlag(_ values: [String]) {
            args.insert(contentsOf: values, at: args.count - 1)
        }
        func insertConfig(_ keyValue: String) {
            insertPromptScopedFlag(["-c", keyValue])
        }

        if yoloMode {
            insertPromptScopedFlag(["--yolo"])
        }
        if let model = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            insertPromptScopedFlag(["--model", model])
        }
        if let effort = modelReasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !effort.isEmpty {
            insertConfig("model_reasoning_effort=\(effort)")
        }
        if let provider = modelProviderOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty {
            insertConfig("model_provider=\"\(escapedTomlString(provider))\"")
        }
        insertConfig("fast_mode=\(fastMode ? "true" : "false")")
        if shouldInjectOpenAIResponsesWireAPI(
            modelProviderOverride: modelProviderOverride,
            preferOpenAIResponsesWireAPI: preferOpenAIResponsesWireAPI
        ) {
            // Opt-in safety switch: force modern OpenAI wire API for Codex CLI.
            // Newer Codex config schemas require an explicit provider `name` field.
            insertConfig("model_providers.openai.name=\"openai\"")
            insertConfig("model_providers.openai.wire_api=\"responses\"")
        }
        insertConfig("approval_policy=\"\(askForApproval)\"")
        return args
    }

    static func shouldInjectOpenAIResponsesWireAPI(
        modelProviderOverride: String?,
        preferOpenAIResponsesWireAPI: Bool
    ) -> Bool {
        guard preferOpenAIResponsesWireAPI else { return false }
        let provider = modelProviderOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if provider.isEmpty { return true }
        return provider == "openai"
    }

    static func escapedTomlString(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func repairCodexConfigIfNeeded(environment: [String: String]) {
        let codexHome = resolvedCodexHome(from: environment)
        let configPath = (codexHome as NSString).appendingPathComponent("config.toml")
        guard FileManager.default.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8)
        else { return }

        let fixed = repairedCodexConfigContentIfNeeded(content)
        guard fixed != content else { return }
        try? fixed.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    static func resolvedCodexHome(from environment: [String: String]) -> String {
        let raw = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            return raw
        }
        return "\(NSHomeDirectory())/.codex"
    }

    static func repairedCodexConfigContentIfNeeded(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return content }

        let updated = repairOpenAIProviderSection(in: lines)
        let normalizedUpdated = updated.joined(separator: "\n")
        guard normalizedUpdated != content.trimmingCharacters(in: .newlines) else {
            return content
        }
        if content.hasSuffix("\n") {
            return normalizedUpdated + "\n"
        }
        return normalizedUpdated
    }

    private static func repairOpenAIProviderSection(in lines: [String]) -> [String] {
        let normalizedSectionHeaders: Set<String> = [
            "[model_providers.openai]",
            "[model_providers.\"openai\"]"
        ]

        var startIndex: Int?
        for (idx, line) in lines.enumerated() {
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedSectionHeaders.contains(normalized) {
                startIndex = idx
                break
            }
        }
        guard let sectionStart = startIndex else { return lines }

        var sectionEnd = lines.count
        if sectionStart + 1 < lines.count {
            for idx in (sectionStart + 1)..<lines.count {
                let trimmed = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    sectionEnd = idx
                    break
                }
            }
        }

        for idx in (sectionStart + 1)..<sectionEnd {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("name")
                && (trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces).hasPrefix("=") || trimmed == "name")
            {
                return lines
            }
        }

        var updated = lines
        updated.insert("name = \"openai\"", at: sectionStart + 1)
        return updated
    }

}
