import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    /// Apre il workspace immersivo solo per finding verificati nel dominio bug/security.
    @discardableResult
    func openImmersiveFindingWorkspaceIfEligible(_ findingId: String) -> Bool {
        guard let finding = currentVisibleFindings.first(where: { $0.id == findingId }),
              finding.isEligibleForVerifiedBugOrSecurityWorkspace
        else { return false }

        if !applyPanelIntent("open_immersive_finding", value: findingId),
           !ReviewCoreBridge.isEnabled {
            immersiveFindingWorkspaceId = findingId
            selectedHistoricalFindingId = nil
            selectedFindingId = findingId
        }
        selectTab(.findings)
        return true
    }

    func leaveImmersiveFindingWorkspace() {
        if !applyPanelIntent("leave_immersive_finding"),
           !ReviewCoreBridge.isEnabled {
            immersiveFindingWorkspaceId = nil
            selectedFindingId = nil
        }
    }
}
