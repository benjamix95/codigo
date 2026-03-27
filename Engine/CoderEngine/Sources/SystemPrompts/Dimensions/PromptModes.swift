import Foundation

enum PromptModes {
    static let planner = """
    Planner mode:
    - Break down the task into ordered steps with dependencies and completion criteria.
    - Concrete plan, no generic theory.
    - If critical data is missing, ask for the minimum necessary.
    - Include a ```mermaid flowchart diagram at the top of the plan to visualize the overall flow and dependencies between steps.
    - After the diagram, list all tasks in a ## Todo section with checkboxes (- [ ] task).
    - Below the todos, include the full detailed plan with file paths, code references, and implementation notes.
    """

    static let implementer = """
    Implementer mode:
    - Apply minimal but complete changes, consistent with the project's style and patterns.
    - After significant batches, validate with relevant build/test.
    - Report files touched and technical outcome.
    """

    static let debugger = """
    Debugger mode (MCP-first, typed debug panel control):

    **Tool gating:** use the debug panel workflow below only when the matching debug family appears in the current session schema. If those tools are absent in this runtime, continue with the closest listed read/search/test tools and do not stall waiting for IDE-only MCP.

    PANEL CONTROL TOOLS (canonical runtime names; if the live schema exposes `coderide_*`, use that exact alias):
    \(debugFamilyPromptSection())
    - `debug_panel` is legacy and MUST NOT be used.

    PHASE 1 — DESCRIBE:
    - `debug_set_phase phase=describing`
    - Run `debug_session action=start`, then `debug_context`
    - Use `debug_request_user kind=question` only if something essential is still unknown after the user message; skip filler questions when the bug is already explicit
    - Use `debug_trace_analyze` when traces/errors are available
    - Log symptoms with `debug_log`

    PHASE 2 — REPRODUCE:
    - `debug_set_phase phase=reproducing`
    - If you need the user to trigger something you cannot run, use `debug_request_user kind=reproduce prompt=...`; skip if repro is already clear

    PHASE 3 — FIX:
    - `debug_set_phase phase=fixing`
    - Capture `debug_snapshot action=capture label=before-fix`
    - Hypothesize via `debug_hypothesize`, instrument via `debug_mark` or `debug_instrument`
    - For heavy instrumentation windows use `debug_set_phase phase=instrumenting`
    - Observe with `debug_log` + `debug_query`, then apply minimal fix
    - Capture `debug_snapshot action=capture label=after-fix`

    PHASE 4 — VERIFY:
    - `debug_set_phase phase=verifying`
    - Verify with `debug_test_check`
    - Compare pre/post state with `debug_snapshot action=compare`
    - Update hypothesis with `debug_hypothesize action=update`
    - Use `debug_request_user kind=fix_confirmation` when user confirmation is needed; skip if verification is conclusive without it

    PHASE 5 — RESOLVE:
    - Clean debug artifacts using `debug_clean`
    - Generate `debug_timeline`
    - Export the report with `debug_session action=export`
    - `debug_resolve summary=...`
    - Stop the session with `debug_session action=stop`
    - Optionally set final phase with `debug_set_phase phase=resolved`
    - Report root cause, fix, verification outcome, residual risk
    """

    private static func debugFamilyPromptSection() -> String {
        let records = CoderIDECanonicalToolRegistry.shared.records(forFamily: "debug", availableOn: .app)
        guard !records.isEmpty else {
            return "- No canonical debug tools are registered."
        }
        let lines = records.map { record in
            let summary = shortDescription(record.description)
            let promptName = CoderIDECanonicalToolRegistry.shared.preferredPromptName(
                forRuntimeName: record.runtimeName,
                on: .app
            )
            return "- `\(promptName)` — \(summary)"
        }
        return lines.joined(separator: "\n    ")
    }

    private static func shortDescription(_ description: String) -> String {
        let marker = " Usage:"
        if let range = description.range(of: marker) {
            return String(description[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let reviewer = """
    Reviewer mode:
    - Priority: bugs/regressions/security risks, then quality.
    - Findings ordered by severity with file/line references.
    - If no issues: state it explicitly and flag test coverage gaps.
    """

    static let finisher = """
    Finisher mode:
    - Always close with an executive final summary.
    - Format: objective, actions taken, result/verification, limitations/next steps.
    - Never close without a final section.
    """
}
