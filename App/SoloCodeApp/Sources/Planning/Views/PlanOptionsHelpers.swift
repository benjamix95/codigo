import Foundation

func isClarificationSelectionComplete(
    question: PlanClarificationQuestion,
    selectedOption: PlanClarificationOption?,
    selectedOptions: Set<String>? = nil,
    customText: String?
) -> Bool {
    if question.isMultiSelect {
        let selectedIds = selectedOptions ?? Set()
        guard !selectedIds.isEmpty else { return false }
        let selectedIncludesOther = question.options.contains {
            selectedIds.contains($0.id) && PlanOptionsParser.isOtherLikeClarificationOption($0)
        }
        if selectedIncludesOther {
            let custom = customText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !custom.isEmpty
        }
        return true
    }
    guard let selectedOption else { return false }
    if PlanOptionsParser.isOtherLikeClarificationOption(selectedOption) {
        let custom = customText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !custom.isEmpty
    }
    return true
}
