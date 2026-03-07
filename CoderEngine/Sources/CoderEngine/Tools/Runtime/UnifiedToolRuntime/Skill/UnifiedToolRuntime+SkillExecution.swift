import Foundation

extension UnifiedToolRuntime {

    func executeSkill(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let skillName = (call.args["skill"] ?? call.args["name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let task = (call.args["task"] ?? call.args["args"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !skillName.isEmpty else {
            return failure(
                "skill tool requires 'skill' or 'name' (e.g. doc, imagegen, code-review). Use mcp_list_tools to discover available skills.",
                errorCode: "missing_argument",
                startDate: startDate,
                payload: ["title": "Missing skill name"]
            )
        }

        guard let skillContent = InstructionPolicyBundle.skillContent(for: skillName) else {
            return failure(
                "No skill '\(skillName)' in ~/.codex/skills, ~/.claude/skills, or ~/.agents/skills. Install with the skill-installer skill.",
                errorCode: "skill_not_found",
                startDate: startDate,
                payload: ["title": "Skill not found", "skill": skillName]
            )
        }

        let codexPath = PathFinder.find(executable: "codex") ?? "/usr/local/bin/codex"
        guard FileManager.default.fileExists(atPath: codexPath) else {
            return failure(
                "Codex CLI not found. Install with: brew install codex",
                errorCode: "codex_not_found",
                startDate: startDate
            )
        }

        let workspacePath = context.workspaceContext.workspacePath.path
        let sandboxMode = context.policy.sandboxMode
        let askForApproval = context.policy.askForApproval
        let userTask = task.isEmpty
            ? "Execute this skill according to its instructions. If the user's request is in the conversation context, use that."
            : task

        let fullPrompt = """
        You are executing the **\(skillName)** skill. Follow these instructions exactly:

        \(skillContent)

        ---

        **Task:** \(userTask)
        """

        var args = ["exec", "--json"]
        if sandboxMode == "danger-full-access" {
            args.append("--yolo")
        } else {
            args.append("--full-auto")
        }
        args += ["-c", "approval_policy=\"\(askForApproval)\""]
        args += ["--sandbox", sandboxMode, "--cd", workspacePath, fullPrompt]

        do {
            let (outputLines, status) = try await ProcessRunner.runCollecting(
                executable: codexPath,
                arguments: args,
                workingDirectory: URL(fileURLWithPath: workspacePath),
                executionController: nil,
                scope: .agent
            )

            let extractedText = Self.extractTextFromCodexOutput(outputLines)
            let output = extractedText.isEmpty
                ? outputLines.joined(separator: "\n")
                : extractedText

            let ok = status == 0
            var payload: [String: String] = [
                "output": String(output.prefix(100_000)),
                "skill": skillName,
            ]
            if !ok {
                payload["status"] = "failed"
                payload["exit_code"] = "\(status)"
            }

            return ToolResult(
                ok: ok,
                payload: payload,
                durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
            )
        } catch {
            return failure(
                error.localizedDescription,
                errorCode: "skill_execution_failed",
                startDate: startDate,
                payload: ["skill": skillName]
            )
        }
    }

    private static func extractTextFromCodexOutput(_ lines: [String]) -> String {
        var textParts: [String] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let delta = json["delta"] as? String, !delta.isEmpty {
                textParts.append(delta)
            }
            if let text = json["text"] as? String, !text.isEmpty {
                textParts.append(text)
            }
            if let content = json["content"] as? String, !content.isEmpty {
                textParts.append(content)
            }
            if let content = json["content"] as? [[String: Any]] {
                for item in content {
                    if let t = item["text"] as? String, !t.isEmpty {
                        textParts.append(t)
                    }
                }
            }
        }
        return textParts.joined()
    }
}
