import CoderEngine
import SwiftUI

extension CodeReviewPanelStore {
    /// Bordo/card tint per righe History allineate a file in lavorazione sul live board.
    func historyRowLiveAccent(for record: HistoricalFindingRecord) -> Color? {
        guard let live = currentHistoricalLiveRunState, live.isRunning else { return nil }
        guard let match = live.files.first(where: {
            Self.historyPathsLikelyEqual($0.path, record.filePath)
        }) else { return nil }
        switch match.status {
        case .running:
            return DesignSystem.Colors.reviewColor
        case .completed:
            return DesignSystem.Colors.success
        case .failed:
            return DesignSystem.Colors.error
        case .idle:
            return Color.secondary
        }
    }

    private static func historyPathsLikelyEqual(_ a: String, _ b: String) -> Bool {
        let ta = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let tb = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if ta.isEmpty || tb.isEmpty { return false }
        if ta == tb { return true }
        let la = (ta as NSString).standardizingPath
        let lb = (tb as NSString).standardizingPath
        if la == lb { return true }
        return (la as NSString).lastPathComponent == (lb as NSString).lastPathComponent
    }
}
