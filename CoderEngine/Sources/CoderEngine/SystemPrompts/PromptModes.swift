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

    PANEL CONTROL TOOLS (canonical):
    - `debug_set_phase` with phase: `describing|reproducing|fixing|instrumenting|verifying|resolved`
    - `debug_request_user` with kind: `question|reproduce` and `prompt`
    - `debug_resolve` with `summary`
    - `debug_panel` is legacy and MUST NOT be used.

    PHASE 1 — DESCRIBE:
    - `debug_set_phase phase=describing`
    - Run `debug_context`, then `debug_session action=start`
    - Log symptoms with `debug_log` and inspect diagnostics with `read_lints`

    PHASE 2 — REPRODUCE:
    - `debug_set_phase phase=reproducing`
    - If user action is required, use `debug_request_user kind=reproduce prompt=...`

    PHASE 3 — FIX:
    - `debug_set_phase phase=fixing`
    - Hypothesize via `debug_hypothesize`, instrument via `debug_mark`
    - For heavy instrumentation windows use `debug_set_phase phase=instrumenting`
    - Observe with `debug_log` + `debug_query`, then apply minimal fix

    PHASE 4 — VERIFY:
    - `debug_set_phase phase=verifying`
    - Verify with `read_lints` and targeted tests/diagnostics
    - Clean debug artifacts using `debug_clean`

    PHASE 5 — RESOLVE:
    - `debug_resolve summary=...`
    - Optionally set final phase with `debug_set_phase phase=resolved`
    - Report root cause, fix, verification outcome, residual risk
    """

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
