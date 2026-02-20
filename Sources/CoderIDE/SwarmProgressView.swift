import SwiftUI

// MARK: - Swarm Progress View (Cursor-style compact header + agent dashboard)

struct SwarmProgressView: View {
    @ObservedObject var store: SwarmProgressStore
    let activities: [TaskActivity]
    let isTaskRunning: Bool

    @State private var hoveredStepId: UUID?

    private var completedSteps: Int {
        store.steps.filter { $0.status == .completed }.count
    }

    private var totalSteps: Int {
        store.steps.count
    }

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }

    private var activeStepName: String? {
        store.steps.first(where: { $0.status == .inProgress })?.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact progress header
            if !store.steps.isEmpty {
                progressHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                // Thin progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 2)

                        Rectangle()
                            .fill(progressBarGradient)
                            .frame(width: geo.size.width * progress, height: 2)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 2)

                // Steps list (compact)
                stepsRow
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            }

            // Live board
            SwarmLiveBoardView(
                activities: activities,
                isTaskRunning: isTaskRunning
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(SwarmProgressColors.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SwarmProgressColors.border)
                .frame(height: 0.5)
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        HStack(spacing: 8) {
            // Swarm icon with subtle glow
            ZStack {
                if isTaskRunning {
                    Circle()
                        .fill(DesignSystem.Colors.swarmColor.opacity(0.15))
                        .frame(width: 24, height: 24)
                }
                Image(systemName: "ant.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.swarmColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("SWARM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text("\(completedSteps)/\(totalSteps)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.swarmColor)
                }

                if let active = activeStepName {
                    Text(active)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isTaskRunning {
                SwarmProgressSpinner()
            } else if completedSteps == totalSteps && totalSteps > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DesignSystem.Colors.success)
            }
        }
    }

    // MARK: - Steps Row (horizontal compact pills)

    private var stepsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.steps) { step in
                    SwarmStepPill(
                        step: step,
                        isHovered: hoveredStepId == step.id,
                        onHover: { hovering in
                            hoveredStepId = hovering ? step.id : nil
                        }
                    )
                }
            }
        }
    }

    // MARK: - Gradient

    private var progressBarGradient: LinearGradient {
        LinearGradient(
            colors: [
                DesignSystem.Colors.swarmColor,
                DesignSystem.Colors.swarmColor.opacity(0.7),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Step Pill

private struct SwarmStepPill: View {
    let step: SwarmStep
    let isHovered: Bool
    let onHover: (Bool) -> Void

    private var statusIcon: String {
        switch step.status {
        case .completed: return "checkmark"
        case .inProgress: return "play.fill"
        case .pending: return "circle"
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success
        case .inProgress: return DesignSystem.Colors.swarmColor
        case .pending: return Color.primary.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch step.status {
        case .completed: return .secondary
        case .inProgress: return .primary
        case .pending: return Color.gray.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(statusColor)

            if isHovered || step.status == .inProgress {
                Text(step.name)
                    .font(
                        .system(size: 10, weight: step.status == .inProgress ? .semibold : .regular)
                    )
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
        }
        .padding(.horizontal, isHovered || step.status == .inProgress ? 8 : 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(pillBackground)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    step.status == .inProgress
                        ? statusColor.opacity(0.3)
                        : Color.clear,
                    lineWidth: 0.5
                )
        )
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: step.status)
        .onHover { hovering in onHover(hovering) }
    }

    private var pillBackground: Color {
        switch step.status {
        case .completed:
            return isHovered
                ? DesignSystem.Colors.success.opacity(0.12)
                : DesignSystem.Colors.success.opacity(0.06)
        case .inProgress:
            return DesignSystem.Colors.swarmColor.opacity(0.1)
        case .pending:
            return isHovered
                ? Color.primary.opacity(0.06)
                : Color.primary.opacity(0.03)
        }
    }
}

// MARK: - Spinner

private struct SwarmProgressSpinner: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.swarmColor.opacity(0.6))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Colors

private enum SwarmProgressColors {
    static let background = Color(nsColor: .controlBackgroundColor).opacity(0.35)
    static let border = Color(nsColor: .separatorColor).opacity(0.4)
}
