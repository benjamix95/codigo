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
    """
}
