import CoderEngine
import SwiftUI

struct ReviewHistoricalLiveWorkerState: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: FindingSeverity
    let status: SwarmCardStatus
    let files: [String]
    let fileCount: Int

    var statusLabel: String {
        status.rawValue.capitalized
    }
}

struct ReviewHistoricalLiveFileState: Identifiable, Equatable {
    let path: String
    let workerIDs: [String]
    let severity: FindingSeverity
    let status: SwarmCardStatus

    var id: String { path }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var statusLabel: String {
        status.rawValue.capitalized
    }
}

struct ReviewHistoricalLiveBoardState: Equatable {
    let title: String
    let subtitle: String
    let pipeline: ReviewPipelineJobState
    let workers: [ReviewHistoricalLiveWorkerState]
    let files: [ReviewHistoricalLiveFileState]
    let isRunning: Bool
}

struct ReviewPanelHistoricalLiveBoard: View {
    let state: ReviewHistoricalLiveBoardState
    let scanDepth: ReviewScanDepth?
    let onOpenFileAtLocation: (String, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ReviewPipelineJobCard(state: state.pipeline, scanDepth: scanDepth)
            if !state.files.isEmpty {
                filesSection
            }
            if !state.workers.isEmpty {
                workersSection
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    (state.isRunning ? DesignSystem.Colors.reviewColor : DesignSystem.Colors.success).opacity(0.25),
                    lineWidth: 0.8
                )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: state.isRunning ? "waveform.path.ecg" : "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.isRunning ? DesignSystem.Colors.reviewColor : DesignSystem.Colors.success)
                Text(state.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }
            Text(state.subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Files In Analysis", count: state.files.count)
            ForEach(state.files, id: \.id) { file in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(reviewSeverityColor(file.severity))
                        .frame(width: 2.5)
                        .padding(.vertical, 4)

                    Button {
                        onOpenFileAtLocation(file.path, nil)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.fileName)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(file.path)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            badgesRow(file)
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 6)
                        .padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.24))
                )
            }
        }
    }

    private var workersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Active Workers / Tools", count: state.workers.count)
            ForEach(state.workers, id: \.id) { worker in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(reviewSeverityColor(worker.severity))
                        .frame(width: 2.5)
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(worker.title)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer()
                            statusBadge(worker.statusLabel, color: statusColor(worker.status))
                        }
                        Text(worker.detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !worker.files.isEmpty {
                            Text(worker.files.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " • "))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.24))
                )
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Spacer()
            Text("\(count)")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
    }

    private func badgesRow(_ file: ReviewHistoricalLiveFileState) -> some View {
        HStack(spacing: 5) {
            statusBadge(file.statusLabel, color: statusColor(file.status))
            statusBadge(file.severity.rawValue.capitalized, color: reviewSeverityColor(file.severity))
            if file.workerIDs.count > 1 {
                statusBadge("\(file.workerIDs.count) workers", color: DesignSystem.Colors.info)
            } else if let worker = file.workerIDs.first {
                statusBadge(worker, color: DesignSystem.Colors.info)
            }
        }
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func statusColor(_ status: SwarmCardStatus) -> Color {
        switch status {
        case .running:
            return DesignSystem.Colors.reviewColor
        case .completed:
            return DesignSystem.Colors.success
        case .failed:
            return DesignSystem.Colors.error
        case .idle:
            return .secondary
        }
    }
}
