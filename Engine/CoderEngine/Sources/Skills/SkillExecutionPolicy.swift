import Foundation

enum SkillExecutionPolicy {
    private static let defaultExecutionTimeoutSeconds = 20
    static let maxBufferedProviderCharacters = 50_000
    static let maxProviderOutputCharacters = 12_000
    static let maxRuntimeOutputCharacters = 100_000

    static var maxExecutionSeconds: Int {
        guard let override = ProcessInfo.processInfo.environment["CODEX_SKILL_TIMEOUT_SECONDS"],
              let value = Int(override),
              value > 0
        else {
            return defaultExecutionTimeoutSeconds
        }
        return value
    }

    static func buildPrompt(
        skillName: String,
        skillContent: String,
        userTask: String
    ) -> String {
        """
        You are executing the **\(skillName)** skill. Follow these instructions exactly:

        \(skillContent)

        Additional execution constraints:
        - Use direct tools only for this run.
        - Do not call the `skill` tool again from inside a skill.
        - Do not invoke `subagent_*`, `run_agent`, `invoke_swarm`, or orchestration tools from inside a skill.
        - If delegation would help, explain it in the final answer instead of spawning workers.

        ---

        **Task:** \(userTask)
        """
    }
}
