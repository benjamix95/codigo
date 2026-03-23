import CoderEngine
import SwiftUI

func codebaseIndexProgressText(_ progress: IndexingProgress?) -> String? {
    guard let progress else { return nil }
    return progress.percentText
}

extension UsageFooterView {
    @ViewBuilder
    var providerUsageSection: some View {
        let pid = effectiveProviderId ?? ""
        if pid == "codex-cli" {
            codexUsageRow
        } else if pid == "claude-cli" {
            claudeUsageRow
        } else if pid == "gemini-cli" {
            geminiUsageRow
        } else if pid.hasSuffix("-api") {
            apiUsageRow
        } else {
            EmptyView()
        }
    }

    var totalUsageText: String {
        var total = providerUsageStore.apiTokensIn + providerUsageStore.apiTokensOut
        if let c = providerUsageStore.claudeUsage {
            total += (c.inputTokens ?? 0) + (c.outputTokens ?? 0)
        }
        if let g = providerUsageStore.geminiUsage {
            if let t = g.totalTokens {
                total += t
            } else {
                total += (g.inputTokens ?? 0) + (g.outputTokens ?? 0)
            }
        }
        if total > 0 {
            return "Total \(total.formatted()) tok"
        }
        if providerUsageStore.apiEstimatedCost > 0 {
            return String(format: "Total $%.3f", providerUsageStore.apiEstimatedCost)
        }
        return "Total —"
    }

    @ViewBuilder
    var indexProgressLabel: some View {
        if let label = codebaseIndexProgressText(workspaceStore.indexProgress) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .help("Codebase index progress")
        }
    }

    var codexUsageRow: some View {
        HStack(spacing: 6) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }

            if providerUsageStore.isCodexRateLimited {
                Image(systemName: "octagon.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .help(providerUsageStore.codexRateLimitMessage ?? "Rate limit reached")
            } else if providerUsageStore.isCodexUsageHigh {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("High usage — slow down to avoid rate limiting")
            }

            if let u = providerUsageStore.codexUsage {
                if let p5 = u.fiveHourPct {
                    Text("5 h")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(p5))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(p5 >= 100 ? .red : (p5 >= 80 ? .orange : .primary))
                    if let r = u.resetFiveH {
                        Text(r).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                if let pw = u.weeklyPct {
                    Text("·")
                    Text("Week")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(Int(pw))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(pw >= 100 ? .red : (pw >= 80 ? .orange : .primary))
                    if let r = u.resetWeekly {
                        Text(r).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(providerUsageStore.codexUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .help(
            providerUsageStore.isCodexRateLimited
                ? (providerUsageStore.codexRateLimitMessage ?? "Rate limit reached")
                : "Codex CLI usage"
        )
    }

    var claudeUsageRow: some View {
        HStack(spacing: 6) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.claudeUsage {
                if let source = providerUsageStore.claudeUsageSourceLabel, !source.isEmpty {
                    Text(source)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                }
                if let message = providerUsageStore.claudeUsageMessage,
                   !message.isEmpty,
                   providerUsageStore.claudeUsageSourceLabel == "Local session" {
                    Text("fallback")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .help(message)
                }
                if let c = u.sessionCost {
                    Text(c)
                        .font(.system(size: 10, weight: .medium))
                }
                if let i = u.inputTokens, i > 0 {
                    Text("in \(i.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let o = u.outputTokens, o > 0 {
                    Text("out \(o.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let cr = u.cacheReadTokens, cr > 0 {
                    Text("cache \(cr.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if let dur = u.totalDuration, !dur.isEmpty {
                    Text("· \(dur)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if u.sessionCost == nil || u.sessionCost == "$0.0000",
                    (u.inputTokens ?? 0) == 0, (u.outputTokens ?? 0) == 0
                {
                    Text("Empty session")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(providerUsageStore.claudeUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .help("Claude Code — usage online (Admin API) con fallback sessione locale")
    }

    var geminiUsageRow: some View {
        HStack(spacing: 6) {
            if providerUsageStore.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            if let u = providerUsageStore.geminiUsage {
                if let total = u.totalTokens, total > 0 {
                    Text("\(total.formatted()) tok")
                        .font(.system(size: 10, weight: .medium))
                } else if let i = u.inputTokens, i > 0 {
                    Text("in \(i.formatted())")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let o = u.outputTokens, o > 0 {
                        Text("out \(o.formatted())")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if let c = u.sessionCost, !c.isEmpty {
                    Text(c)
                        .font(.system(size: 10, weight: .medium))
                }
                if let note = u.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            } else {
                Text(providerUsageStore.geminiUsageMessage ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .help("Gemini CLI — session local usage")
    }

    var apiUsageRow: some View {
        HStack(spacing: 8) {
            Text("\(providerUsageStore.apiTokensIn + providerUsageStore.apiTokensOut) tok")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if providerUsageStore.apiEstimatedCost > 0 {
                Text(String(format: "$%.3f", providerUsageStore.apiEstimatedCost))
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }

    var contextSection: some View {
        let (tokens, size, pct) = contextEstimateSnapshot
        let isHighUsage = pct >= 0.7
        let isCritical = pct >= 0.9
        return HStack(spacing: 6) {
            CircularProgressView(progress: pct, lineWidth: 1.8, size: 15)
                .animation(.easeOut(duration: 0.18), value: pct)
            Text(formatContextPercentLabel(pct))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isCritical ? DesignSystem.Colors.error : (isHighUsage ? .orange : .secondary))
            Text("\(tokens.formatted()) / \((size / 1000).formatted())k")
                .font(.system(size: 10))
                .foregroundStyle(isCritical ? DesignSystem.Colors.error.opacity(0.7) : .secondary)
            if isCritical {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help("Context window almost full — conversation will be summarized automatically")
            }
        }
        .help(formatContextPercentHelpText(pct))
    }
}
