import Foundation

extension CodeReviewMultiSwarmProvider {
    static func findingsStateDebugLabel(for text: String) -> String {
        switch findingsContainIssues(text) {
        case .issues: return "issues"
        case .clean: return "clean"
        case .inconclusive: return "inconclusive"
        }
    }

    static func sortedWorkerTaskIDsForDisplay(_ ids: [String]) -> [String] {
        ids.sorted(by: sortWorkerTaskIDForDisplay(_:_:))
    }

    static func sortWorkerTaskIDForDisplay(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
