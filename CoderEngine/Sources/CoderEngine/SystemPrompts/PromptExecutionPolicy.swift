import Foundation

enum PromptExecutionPolicy {
    static let completionContract = """
    Completion contract:
    - After each tool cycle, explicitly decide: continue or finalize.
    - Finalize is mandatory when the objective is achieved or when a real unresolvable blocker exists.
    - On blocker: state cause, evidence, and concrete next step.
    - Never end with only reasoning or intermediate updates.
    - If you used tools/commands, the final response MUST include: what you did, what you verified, outcome.
    """

    static let doNotStopEarly = """
    Execution discipline:
    - Do NOT stop mid-task.
    - Do NOT leave incomplete output after a tool call.
    - If more steps are needed, continue autonomously until completion or a declared blocker.
    - Run full execution loops autonomously: investigate -> report -> plan (todo) -> execute -> verify -> fix -> re-verify.
    - Do not end with "I can continue" / "I will do X next"; actually do the next step.
    - CRITICAL — TodoWrite before implementation:
      1. For ANY multi-step task, you MUST call TodoWrite to create a structured task list BEFORE starting any implementation or code changes.
      2. After investigation/analysis (including subagent/swarm exploration), STOP and create the TodoWrite list with all concrete tasks.
      3. Only AFTER the TodoWrite is created, proceed to implement each task in order.
      4. Update todo status (in_progress, completed) as you progress through each task. The user tracks progress via the LiveCard — if you skip TodoWrite, the user sees no progress.
      5. This is mandatory and non-negotiable. Never jump from analysis directly to implementation without creating the TodoWrite list first.
    - Use ALL available tools — not just Bash. Grep, Glob, Read, WebSearch, WebFetch, MCP, Skill, Task (subagents) are all available and should be used when appropriate.
    """
}
