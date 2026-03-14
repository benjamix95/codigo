import CoderEngine
import SwiftUI

extension HistoricalFindingRecord {
    var historyBucket: ReviewFindingHistoryStatusFilter {
        switch status {
        case .candidate, .verifying, .verified, .needsManualReview:
            return .open
        case .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixFailed, .rollbackApplied:
            return .inProgress
        case .fixedVerified, .closed, .rejected:
            return .resolved
        }
    }

    var historyStatusLabel: String {
        status.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var historyStatusColor: Color {
        switch historyBucket {
        case .resumeQueue:
            return DesignSystem.Colors.warning
        case .open:
            return DesignSystem.Colors.reviewColor
        case .inProgress:
            return DesignSystem.Colors.info
        case .resolved:
            return DesignSystem.Colors.success
        case .all:
            return .secondary
        }
    }

    var domainLabel: String {
        domain == .security ? "Security" : "Bug"
    }

    var sourceLabel: String {
        sourceOrigin?.isEmpty == false ? sourceOrigin! : domain.rawValue
    }

    var latestLifecycleLabel: String {
        if let verdict = revalidationVerdict?.rawValue {
            return verdict.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let patchApplyStatus = patchApplyStatus?.rawValue {
            return patchApplyStatus.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return historyStatusLabel
    }

    func matches(statusFilter: ReviewFindingHistoryStatusFilter) -> Bool {
        switch statusFilter {
        case .resumeQueue:
            return resumeEligible
        case .open:
            return historyBucket == .open
        case .inProgress:
            return historyBucket == .inProgress
        case .resolved:
            return historyBucket == .resolved
        case .all:
            return true
        }
    }

    func matches(domainFilter: ReviewFindingHistoryDomainFilter) -> Bool {
        switch domainFilter {
        case .all:
            return true
        case .bug:
            return domain == .bug
        case .security:
            return domain == .security
        }
    }

    func matches(severityFilter: ReviewFindingHistorySeverityFilter) -> Bool {
        switch severityFilter {
        case .all:
            return true
        case .critical:
            return severity == .critical
        case .high:
            return severity == .high
        case .medium:
            return severity == .medium
        case .low:
            return severity == .low
        case .info:
            return severity == .info
        }
    }
}

struct ReviewPanelHistoricalFindingDetail: View {
    @ObservedObject var store: CodeReviewPanelStore
    let record: HistoricalFindingRecord
    let onOpenFileAtLocation: (String, Int?) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.2)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    locationSection
                    summarySection
                    lifecycleSection
                    chronologySection
                    actionsSection
                }
                .padding(12)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
            }
            .buttonStyle(.plain)

            Text("History")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)

            Spacer()

            Text(record.findingId.prefix(8))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("LOCATION")
            Button {
                onOpenFileAtLocation(record.filePath, record.lineStart)
            } label: {
                Text("\(record.filePath)\(record.lineStart.map { ":\($0)" } ?? "")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(store.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("SUMMARY")
            Text(record.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            Text(record.summary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lifecycleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("LIFECYCLE")
            infoRow("Domain", value: record.domainLabel)
            infoRow("Origin", value: record.sourceLabel)
            infoRow("Status", value: record.historyStatusLabel)
            infoRow("Patch", value: record.patchApplyStatus?.rawValue ?? "none")
            infoRow("Revalidation", value: record.revalidationVerdict?.rawValue ?? "none")
            infoRow("Updated", value: relativeDate(record.updatedAt))
            if let resolvedAt = record.resolvedAt {
                infoRow("Resolved", value: relativeDate(resolvedAt))
            }
            if let closedReason = record.closedReason, !closedReason.isEmpty {
                infoRow("Closed Reason", value: closedReason)
            }
        }
    }

    private var chronologySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("CHRONOLOGY")
            if record.timeline.isEmpty {
                Text("Nessun evento storico disponibile per questo finding.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.quaternary)
            } else {
                ForEach(record.timeline, id: \.id) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(record.historyStatusColor)
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.eventType)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(relativeDate(item.createdAt))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                            }
                            if let detail = item.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("ACTIONS")
            if record.resumeEligible {
                Button {
                    Task { await store.resumeHistoricalFinding(record) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 10))
                        Text("Resume Finding")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(store.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("Il finding è già risolto o chiuso. Resta consultabile nello storico.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(.system(size: 9.5))
                .foregroundStyle(.primary)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
