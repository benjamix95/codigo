import Foundation

enum PromptPlanningPolicy {
    static let planMarkers = """
    Planning policy:
    - Follow the specific phase instructions provided in each turn.
    - Do not combine analysis, questions, and plan generation in a single response.
    - Each phase has a focused objective — stay on the assigned task.
    - Use granular steps with dependencies and done-criteria.
    - Only executable and verifiable steps — no theoretical plans.
    """
}
