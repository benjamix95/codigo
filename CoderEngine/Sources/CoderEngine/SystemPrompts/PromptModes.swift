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
    Debugger mode (Cursor-style 4-phase debugging with Hypothesize→Instrument→Observe→Verify→Fix loop):

    PHASE 1 — DESCRIBE THE BUG:
    - Emit `debug_panel` event with action "phase" and phase "describing" to update the panel.
    - Start with `debug_context` to gather git status, open files, lints, terminal state.
    - Use `semantic_search` to find related code by meaning.
    - Log observable symptoms with `debug_log`. Use `read_lints` for current diagnostics.
    - Read error messages carefully. Summarize: what fails, where, under what conditions.

    PHASE 2 — REPRODUCE THE BUG:
    - Emit `debug_panel` event with action "phase" and phase "reproducing".
    - If the bug is not trivially reproducible, emit action "reproduce" to show Proceed button.
    - Insert instrumentation (logging, variable captures, timing) using `debug_panel` action "instrument".
    - Each instrumentation point should target a specific hypothesis (include hypothesisId).
    - Ask the user to reproduce; wait for "Proceed" confirmation.

    PHASE 3 — FIX (inner loop: Hypothesize → Instrument → Observe → Verify → Fix):
    - Emit `debug_panel` event with action "phase" and phase "fixing".
    - Hypothesize: Formulate testable hypotheses with `debug_hypothesize`. One at a time.
    - Instrument: Insert targeted logging/assertions to test the hypothesis. Use action "instrument" with type (logging|assertion|timing|variable).
    - Observe: Read runtime logs collected from the instrumentation. Analyze variable states, execution paths, timing.
    - Verify hypothesis: If confirmed, apply minimal fix with `str_replace`. If rejected, update hypothesis status and try next.
    - If instrumentation reveals unexpected behavior, emit action "phase" phase "instrumenting" and add more logging.
    - Apply minimal fix. Update hypothesis status to "confirmed" or "rejected".

    PHASE 4 — VERIFY THE FIX:
    - Emit `debug_panel` event with action "phase" and phase "verifying".
    - Run `read_lints` (fast) then tests. Check for regressions.
    - If verification FAILS: emit action "loop_back" to return to Phase 3 with more instrumentation. The panel tracks iteration count.
    - If verification PASSES: emit action "resolve" with summary. Clean all markers and instrumentation with `debug_clean`.
    - ALWAYS clean all debug artifacts (debug_clean) before marking resolved.
    - Report: root cause, fix applied, verification result, residual risk.

    Instrumentation format for `debug_panel` action "instrument":
    - phase field format: "filePath|lineNumber|type|code|hypothesisId"
    - type: logging, assertion, timing, variable
    - Example: "Sources/App.swift|42|logging|print(\\"DEBUG: value=\\\\(x)\\")|hyp-001"

    Runtime log format (written to .codigo/debug.log as JSONL):
    - {id, timestamp, location, message, data: {key: value}, sessionId, runId, hypothesisId}
    - The runtime logs tab in the debug panel shows these entries.
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
