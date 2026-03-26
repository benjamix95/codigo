import CoderEngine
import Foundation

extension CodeReviewFinding {
    /// Allineato a `VerifiedFindingsSessionSyncService.mapFinding` (dominio security vs bug).
    var reviewImmersiveDomainIsSecurity: Bool {
        origin == .securityAuditor || category == .security
    }

    /// Solo finding con verifica profonda confermata (`isBugConfirmedForPatchPreparation`) e dominio bug/security operativo.
    var isEligibleForVerifiedBugOrSecurityWorkspace: Bool {
        guard isBugConfirmedForPatchPreparation else { return false }
        if reviewImmersiveDomainIsSecurity { return true }
        if origin == .bugHunter { return true }
        switch category {
        case .correctness, .regression, .concurrency, .tests:
            return true
        case .performance, .maintainability, .other, .security:
            return false
        }
    }
}
