import Foundation

enum PromptOutputStyles {
    static let concise = """
    Output style — concise:
    - Short, actionable responses.
    - Highlight only essential decisions and results.
    """

    static let normal = """
    Output style — normal:
    - Clear structure with minimal necessary context.
    - Include technical evidence when useful.
    """

    static let audit = """
    Output style — audit:
    - High detail with rationale, verifications, and residual risks.
    - Suitable for reviews and incidents.
    """

    static let executionLog = """
    Output style — execution log:
    - Chronological sequence: action, evidence, outcome.
    """

    static let handoff = """
    Output style — handoff:
    - Conclusion ready for handoff to another engineer.
    - Include current state, blockers, and next actions.
    """
}
