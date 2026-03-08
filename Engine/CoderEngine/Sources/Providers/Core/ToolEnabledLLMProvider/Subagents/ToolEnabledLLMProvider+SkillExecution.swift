import Foundation

extension ToolEnabledLLMProvider {

    /// Execute the skill tool by spawning a subagent with the skill's SKILL.md instructions.
    func executeSkillTool(marker: CoderIDEMarker, context: WorkspaceContext) async -> [StreamEvent] {
        let skillName = marker.payload["skill"] ?? marker.payload["name"] ?? marker.payload["skill_name"] ?? ""
        let task = marker.payload["task"] ?? marker.payload["prompt"] ?? marker.payload["args"] ?? ""
        let toolCallId = marker.payload["id"] ?? UUID().uuidString
        let skillId = "skill-\(skillName)-\(UUID().uuidString.prefix(8))"
        var events: [StreamEvent] = []

        guard !skillName.isEmpty else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "Missing skill name",
                "detail": "skill tool requires 'skill' or 'name' (e.g. doc, imagegen, transcribe). Use mcp_list_tools to discover available skills.",
                "status": "failed",
                "error_code": "missing_argument"
            ])]
        }

        guard let skillContent = InstructionPolicyBundle.skillContent(for: skillName) else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "Skill not found",
                "detail": "No skill '\(skillName)' in ~/.codex/skills, ~/.claude/skills, or ~/.agents/skills. Install with the skill-installer skill.",
                "status": "failed",
                "error_code": "skill_not_found"
            ])]
        }

        events.append(.raw(type: "agent", payload: [
            "title": "Skill: \(skillName)",
            "detail": "started",
            "swarm_id": skillId,
            "group_id": "swarm-\(skillId)",
            "tool_call_id": toolCallId,
            "status": "started"
        ]))

        let startDate = Date()
        let userPrompt = task.isEmpty
            ? "Execute this skill according to its instructions. If the user's request is in the conversation context, use that."
            : task

        do {
            let subagentBase = subagentProviderFactory?() ?? base
            let subagentRuntime = UnifiedToolRuntime(
                executionController: nil,
                executionScope: .swarm,
                workspacePaths: context.workspacePaths
            )
            let subagentProvider = ToolEnabledLLMProvider(
                base: subagentBase,
                runtime: subagentRuntime,
                policy: policy,
                executionScope: .swarm,
                maxToolRounds: 120,
                subagentProviderFactory: nil
            )
            let systemPrompt = """
            You are executing the **\(skillName)** skill. Follow these instructions exactly:

            \(skillContent)

            Execute the user's task using the tools available to you (read, grep, bash, etc.).
            """
            let fullPrompt = "\(systemPrompt)\n\n---\n\n**Task:** \(userPrompt)"

            var fullTextParts: [String] = []
            var fullTextLength = 0
            let stream = try await subagentProvider.send(
                prompt: fullPrompt, context: context, imageURLs: nil
            )
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    if fullTextLength + delta.count <= 50_000 {
                        fullTextParts.append(delta)
                        fullTextLength += delta.count
                    }
                case .raw(let type, var payload):
                    payload["swarm_id"] = skillId
                    payload["group_id"] = "swarm-\(skillId)"
                    events.append(.raw(type: type, payload: payload))
                default:
                    break
                }
            }

            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            let output = String(fullTextParts.joined().prefix(12000))

            events.append(.raw(type: "agent", payload: [
                "title": "Skill: \(skillName)",
                "detail": "completed",
                "swarm_id": skillId,
                "group_id": "swarm-\(skillId)",
                "tool_call_id": toolCallId,
                "status": "completed",
                "duration_ms": "\(durationMs)"
            ]))
            events.append(.raw(type: "tool_result", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "\(skillName) completed",
                "detail": "Skill \(skillName) completed in \(durationMs)ms",
                "output": output,
                "status": "completed",
                "skill": skillName,
                "duration_ms": "\(durationMs)"
            ]))
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)
            events.append(.raw(type: "agent", payload: [
                "title": "Skill: \(skillName)",
                "detail": "failed",
                "swarm_id": skillId,
                "group_id": "swarm-\(skillId)",
                "tool_call_id": toolCallId,
                "status": "failed"
            ]))
            events.append(.raw(type: "tool_result", payload: [
                "id": toolCallId,
                "name": "skill",
                "title": "\(skillName) failed",
                "detail": error.localizedDescription,
                "output": "Skill \(skillName) failed: \(error.localizedDescription)",
                "status": "failed",
                "skill": skillName,
                "duration_ms": "\(durationMs)"
            ]))
        }

        return events
    }
}
