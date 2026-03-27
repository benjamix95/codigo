import CoderEngine
import Foundation

enum ReviewPanelHistoricalFindingsLocalReducer {
    static func merge(
        primary: [HistoricalFindingRecord],
        fallback: [HistoricalFindingRecord]
    ) -> [HistoricalFindingRecord] {
        var merged = Dictionary(uniqueKeysWithValues: primary.map { ($0.findingId, $0) })
        for record in fallback {
            guard let existing = merged[record.findingId] else {
                merged[record.findingId] = record
                continue
            }
            if record.updatedAt > existing.updatedAt {
                merged[record.findingId] = record
            }
        }
        return merged.values.sorted(by: compare)
    }

    static func shape(_ records: [HistoricalFindingRecord]) -> [HistoricalFindingRecord] {
        var merged: [String: HistoricalFindingRecord] = [:]
        for record in records {
            let normalized = HistoricalFindingRecord(
                findingId: record.findingId,
                sessionId: record.sessionId,
                workspaceId: record.workspaceId,
                domain: record.domain,
                severity: record.severity,
                title: record.title,
                summary: record.summary,
                status: record.status,
                filePath: record.filePath,
                lineStart: record.lineStart,
                sourceOrigin: record.sourceOrigin,
                closedReason: record.closedReason,
                patchId: record.patchId,
                patchApplyStatus: record.patchApplyStatus,
                revalidationReportId: record.revalidationReportId,
                revalidationVerdict: record.revalidationVerdict,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                resolvedAt: record.resolvedAt,
                resumeEligible: record.resumeEligible,
                timeline: record.timeline.sorted { $0.createdAt < $1.createdAt }
            )
            if let existing = merged[record.findingId], existing.updatedAt >= normalized.updatedAt {
                continue
            }
            merged[record.findingId] = normalized
        }
        return merged.values.sorted(by: compare)
    }

    private static func compare(
        lhs: HistoricalFindingRecord,
        rhs: HistoricalFindingRecord
    ) -> Bool {
        switch (lhs.resumeEligible, rhs.resumeEligible) {
        case (true, false):
            return true
        case (false, true):
            return false
        default:
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}
