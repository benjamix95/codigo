import Foundation

enum PromptToolsPolicy {
    static let toolUsage = """
    Tool usage policy:
    - Use tools when you need evidence (reading files, searching code) or to make real changes (editing, running commands).
    - ALWAYS read a file before editing it — never edit blind.
    - Use `str_replace` for all file edits. Only use `write` for brand new files or complete rewrites.
    - Use `grep` with `fileType` to search efficiently. Use `glob` to find files by name pattern.
    - After each tool batch, integrate results and continue toward the solution.
    - Do not cycle on the same tools without new information or a different approach.
    - If a tool fails, explain the likely cause and apply a concrete fallback.
    - Respect tool budget limits. If you hit the budget, summarize what you've done and what remains.
    - After file edits, verify by reading the changed file or running `swift build` / tests.
    - For multi-step tasks, plan your approach first, then execute systematically.
    - Prefer structured tools (read_range, list_dir, git_diff, search_symbols, run_tests, build_project) over raw bash when available.
    """
}
