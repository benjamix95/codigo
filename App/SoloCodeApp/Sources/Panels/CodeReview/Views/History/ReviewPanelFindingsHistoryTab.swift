import AppKit
import CoderEngine
import SwiftUI

enum ReviewFindingHistoryStatusFilter: String, CaseIterable, Identifiable {
    case resumeQueue = "Resume"
    case open = "Open"
    case inProgress = "In Progress"
    case resolved = "Resolved"
    case all = "All"

    var id: String { rawValue }
}

enum ReviewFindingHistoryDomainFilter: String, CaseIterable, Identifiable {
    case all = "All Domains"
    case bug = "Bug"
    case security = "Security"

    var id: String { rawValue }
}

enum ReviewFindingHistorySeverityFilter: String, CaseIterable, Identifiable {
    case all = "All Severities"
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case info = "Info"

    var id: String { rawValue }
}

struct ReviewPanelFindingsHistoryTab: View {
    @ObservedObject var store: CodeReviewPanelStore
    let onOpenFileAtLocation: (String, Int?) -> Void

    var body: some View {
        if let selected = store.selectedHistoricalFinding {
            ReviewPanelHistoricalFindingDetail(
                store: store,
                record: selected,
                onOpenFileAtLocation: onOpenFileAtLocation,
                onBack: { store.clearSelectedHistoricalFinding() }
            )
        } else {
            content
                .task(id: store.findingsHistoryRefreshKey) {
                    await store.refreshHistoricalFindings()
                }
        }
    }

    private var content: some View {
        let liveState = store.currentHistoricalLiveRunState
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                filtersCard

                if let liveState {
                    ReviewPanelHistoricalLiveBoard(
                        state: liveState,
                        onOpenFileAtLocation: onOpenFileAtLocation
                    )
                    .id(store.historyLiveRefreshKey)
                }

                if store.isHistoryLoading && store.historyRecords.isEmpty && liveState == nil {
                    loadingCard
                } else if !store.historicalResumeQueue.isEmpty && store.historyStatusFilter == .all {
                    recordsSection(
                        title: "Resume Queue",
                        subtitle: liveState == nil
                            ? "Finding aperti o incompleti pronti per essere ripresi"
                            : "Finding storici ancora aperti, separati dal run live corrente",
                        records: store.historicalResumeQueue,
                        showResumeBadge: true
                    )
                }

                let records = store.historyStatusFilter == .all
                    ? store.historicalArchiveRecords
                    : store.filteredHistoricalFindings

                if records.isEmpty {
                    emptyCard
                } else {
                    recordsSection(
                        title: archiveTitle(liveState: liveState),
                        subtitle: archiveSubtitle(liveState: liveState),
                        records: records,
                        showResumeBadge: store.historyStatusFilter == .resumeQueue
                    )
                }
            }
            .padding(12)
        }
    }

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORY FILTERS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)

            HStack(spacing: 8) {
                filterMenu(
                    title: "Status",
                    selection: $store.historyStatusFilter
                )
                filterMenu(
                    title: "Domain",
                    selection: $store.historyDomainFilter
                )
                filterMenu(
                    title: "Severity",
                    selection: $store.historySeverityFilter
                )
                Spacer()
                Button("Refresh") {
                    Task { await store.refreshHistoricalFindings() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if store.currentHistoricalLiveRunState != nil {
                HStack(spacing: 8) {
                    Text("PID \(ProcessInfo.processInfo.processIdentifier)")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.quaternary)
                    Button("Copia comando sample") {
                        let pid = ProcessInfo.processInfo.processIdentifier
                        let cmd = "sample \(pid) 10 -file ~/Desktop/SoloCode_sample.txt"
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    Text("Esegui in Terminale se la UI si blocca durante la review.")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.30))
        )
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Sto caricando lo storico enterprise dei finding dal DB.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.22))
        )
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(store.currentHistoricalLiveRunState == nil ? "No historical findings" : "No archived findings yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(
                store.currentHistoricalLiveRunState == nil
                    ? "Lo storico globale verrà popolato man mano che i finding vengono persistiti."
                    : "Il live board è attivo. L’archivio persistito si aggiorna appena il run viene sincronizzato nel DB."
            )
                .font(.system(size: 9.5))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func recordsSection(
        title: String,
        subtitle: String,
        records: [HistoricalFindingRecord],
        showResumeBadge: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)

            ForEach(records, id: \.id) { record in
                historyRow(record, showResumeBadge: showResumeBadge)
            }
        }
    }

    private func historyRow(
        _ record: HistoricalFindingRecord,
        showResumeBadge: Bool
    ) -> some View {
        Button {
            store.selectHistoricalFinding(record.id)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(record.historyStatusColor)
                    .frame(width: 2.5)
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(URL(fileURLWithPath: record.filePath).lastPathComponent)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let line = record.lineStart {
                            Text("L\(line)")
                                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                        Spacer()
                        Text(record.updatedAt, style: .relative)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }

                    Text(record.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        badge(record.domainLabel, color: record.domain == .security ? DesignSystem.Colors.error : DesignSystem.Colors.warning)
                        badge(record.historyStatusLabel, color: record.historyStatusColor)
                        badge(record.latestLifecycleLabel, color: DesignSystem.Colors.info)
                        if showResumeBadge || record.resumeEligible {
                            badge("Resume", color: DesignSystem.Colors.warning)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.28))
            )
        }
        .buttonStyle(.plain)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func filterMenu<Value: Hashable & CaseIterable & Identifiable & RawRepresentable>(
        title: String,
        selection: Binding<Value>
    ) -> some View where Value.RawValue == String {
        Menu {
            ForEach(Array(Value.allCases), id: \.id) { option in
                Button(option.rawValue) {
                    selection.wrappedValue = option
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                Text(selection.wrappedValue.rawValue)
                    .font(.system(size: 9.5))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private func archiveTitle(
        liveState: ReviewHistoricalLiveBoardState?
    ) -> String {
        if store.historyStatusFilter == .resumeQueue {
            return "Resume Queue"
        }
        return liveState == nil ? "Findings History" : "Historical Archive"
    }

    private func archiveSubtitle(
        liveState: ReviewHistoricalLiveBoardState?
    ) -> String {
        liveState == nil
            ? "Cronologia persistita del workspace"
            : "Storico persistito del workspace sotto al monitoraggio live corrente"
    }
}
