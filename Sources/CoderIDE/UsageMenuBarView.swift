import SwiftUI
import AppKit

struct UsageMenuBarView: View {
    @EnvironmentObject var dashboardStore: AccountUsageDashboardStore
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()

            if dashboardStore.sections.isEmpty {
                Text("Nessun account configurato.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(dashboardStore.sections) { section in
                            providerSection(section)
                        }
                    }
                }
                .frame(maxHeight: 420)
            }

            Divider()
            HStack(spacing: 8) {
                Button("Apri Impostazioni Multi-account") {
                    NotificationCenter.default.post(name: .coderOpenSettingsFromMenuBar, object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Refresh now") {
                    Task { await dashboardStore.refresh() }
                }
                Spacer()
                Button("Apri app") {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .padding(12)
        .frame(width: 430)
        .task {
            await dashboardStore.refresh()
            startPeriodicRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Usage Multi-account")
                .font(.headline)
            let totals = dashboardStore.totals
            Text("Account \(totals.accountCount) • Attivi \(totals.activeCount) • Exhausted \(totals.exhaustedCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "Oggi: $%.2f • %d token", totals.totalDayCost, totals.totalDayTokens))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let updated = dashboardStore.lastUpdatedAt {
                Text("Aggiornato \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func providerSection(_ section: DashboardProviderSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                if let reason = section.lastFailoverReason, !reason.isEmpty {
                    Text("Failover: \(reason)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let at = section.lastSwitchAt {
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if section.provider == .codex {
                codexCreditsBlock(section)
            }

            ForEach(section.rows) { row in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(row.label)
                                .font(.system(size: 11, weight: .medium))
                            if row.isActiveNow {
                                Text("active now")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                            }
                        }
                        Text("\(row.authStatus) • \(row.healthStatus)\(row.isEnabled ? "" : " • disabled")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "D $%.2f • W $%.2f • M $%.2f", row.dayCost, row.weekCost, row.monthCost))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Tok D \(row.dayTokens) • W \(row.weekTokens) • M \(row.monthTokens)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let err = row.lastError, !err.isEmpty {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                            .frame(maxWidth: 130, alignment: .trailing)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func codexCreditsBlock(_ section: DashboardProviderSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch section.codexCredits {
            case .available(let balance, let currency, _):
                Text(String(format: "Crediti: %.2f %@", balance, currency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            default:
                Text("Crediti: N/D")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(
                "Rate 5h: \(formatPct(section.codexRateFiveHour)) • Weekly: \(formatPct(section.codexRateWeekly))"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text("Reset 5h: \(section.codexResetFiveHour ?? "—") • Weekly: \(section.codexResetWeekly ?? "—")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatPct(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    private func startPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                await dashboardStore.refresh()
            }
        }
    }
}

extension Notification.Name {
    static let coderOpenSettingsFromMenuBar = Notification.Name("CoderIDE.OpenSettingsFromMenuBar")
}
