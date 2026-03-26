import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    var orderedSelectedModes: [CodeReviewPanelMode] {
        [CodeReviewPanelMode.securityAudit, .bugFinder].filter { selectedModes.contains($0) }
    }

    var primarySelectedMode: CodeReviewPanelMode {
        orderedSelectedModes.first ?? .bugFinder
    }

    func hasSelectedMode(_ mode: CodeReviewPanelMode) -> Bool {
        selectedModes.contains(mode)
    }

    func toggleModeSelection(_ mode: CodeReviewPanelMode) {
        if selectedModes.contains(mode) {
            if selectedModes.count > 1 {
                selectedModes.remove(mode)
            }
        } else {
            selectedModes.insert(mode)
        }
    }
}
