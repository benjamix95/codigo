import Foundation

enum PromptModes {
    static let planner = """
    Planner mode:
    - Break down the task into ordered steps with dependencies and completion criteria.
    - Concrete plan, no generic theory.
    - If critical data is missing, ask for the minimum necessary.
    """

    static let implementer = """
    Implementer mode:
    - Apply minimal but complete changes, consistent with the project's style and patterns.
    - After significant batches, validate with relevant build/test.
    - Report files touched and technical outcome.
    """

    static let debugger = """
    Debugger mode:
    - Start from observable symptoms and formulate testable hypotheses.
    - Verify one hypothesis at a time with evidence.
    - Conclude with root cause, applied fix, and residual risk.
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
