import Foundation

public enum PromptTemplate: String, CaseIterable, Sendable {
    case bugFix = "bug_fix"
    case featureDelivery = "feature_delivery"
    case codeReview = "code_review"
    case incidentResponse = "incident_response"
    case securityAssessment = "security_assessment"
}

enum PromptTemplates {
    static func template(_ kind: PromptTemplate) -> String {
        switch kind {
        case .bugFix:
            return """
            Template bug_fix:
            1) Reproduce and isolate the root cause.
            2) Apply a minimal complete fix.
            3) Verify with tests/build.
            4) Close with residual risk.
            """
        case .featureDelivery:
            return """
            Template feature_delivery:
            1) Define scope and done criteria.
            2) Implement small verifiable increments.
            3) Document touched files and impact.
            """
        case .codeReview:
            return """
            Template code_review:
            - Findings first, ordered by severity.
            - Include file/line, impact, and suggested fix.
            """
        case .incidentResponse:
            return """
            Template incident_response:
            - Event timeline, blast radius, immediate containment.
            - Recovery, verification, and recurrence prevention.
            """
        case .securityAssessment:
            return """
            Template security_assessment:
            - Concise threat model, attack surfaces, missing controls.
            - Mitigation priorities and post-fix verification.
            """
        }
    }
}
