import Foundation

enum ChatTurnInlineToolGroupingPolicy {
    static func shouldCollapse(category: ChatTurnToolEventGroupCategory) -> Bool {
        switch category {
        case .exploration, .terminal:
            return true
        case .edit:
            return false
        }
    }
}
