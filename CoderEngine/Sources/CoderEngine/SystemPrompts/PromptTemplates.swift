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
            1) Riproduci e isola root cause.
            2) Applica fix minimo completo.
            3) Verifica con test/build.
            4) Chiudi con rischio residuo.
            """
        case .featureDelivery:
            return """
            Template feature_delivery:
            1) Definisci scope e criteri di done.
            2) Implementa incrementi piccoli verificabili.
            3) Documenta file toccati e impatto.
            """
        case .codeReview:
            return """
            Template code_review:
            - Findings prima di tutto, ordinati per severità.
            - Includi file/linee, impatto e fix suggerito.
            """
        case .incidentResponse:
            return """
            Template incident_response:
            - Timeline evento, blast radius, containment immediato.
            - Recovery, verification e prevenzione recidive.
            """
        case .securityAssessment:
            return """
            Template security_assessment:
            - Threat model sintetico, superfici d'attacco, controlli mancanti.
            - Priorità mitigazioni e verifica post-fix.
            """
        }
    }
}
