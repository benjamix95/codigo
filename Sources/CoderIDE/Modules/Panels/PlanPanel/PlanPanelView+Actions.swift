import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension PlanPanelView {
    func savePlanToFile(content: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[PlanPanel] Failed to save plan: \(error.localizedDescription)")
            }
        }
    }
}

struct PlanBuildButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Horizontal 3-step phase progress indicator for the multi-turn plan flow.
struct PlanPhaseProgressView: View {
let phase: PlanFlowPhase

private let planColor = DesignSystem.Colors.planColor

private struct PhaseStep {
    let label: String
    let isActive: Bool
    let isCompleted: Bool
}

private var steps: [PhaseStep] {
    switch phase {
    case .analyzing:
        return [
            PhaseStep(label: "Analysis", isActive: true, isCompleted: false),
            PhaseStep(label: "Questions", isActive: false, isCompleted: false),
            PhaseStep(label: "Plan", isActive: false, isCompleted: false),
        ]
    case .questioning:
        return [
            PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
            PhaseStep(label: "Questions", isActive: true, isCompleted: false),
            PhaseStep(label: "Plan", isActive: false, isCompleted: false),
        ]
    case .generating:
        // Questions step shows as completed only if the phase was visited;
        // otherwise it's skipped (shown as completed to avoid confusion).
        return [
            PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
            PhaseStep(label: "Questions", isActive: false, isCompleted: true),
            PhaseStep(label: "Plan", isActive: true, isCompleted: false),
        ]
    default:
        return [
            PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
            PhaseStep(label: "Questions", isActive: false, isCompleted: true),
            PhaseStep(label: "Plan", isActive: false, isCompleted: true),
        ]
    }
}

var body: some View {
    HStack(spacing: 4) {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            if index > 0 {
                Rectangle()
                    .fill(step.isCompleted || step.isActive
                              ? planColor.opacity(0.6)
                              : Color.secondary.opacity(0.2))
                    .frame(height: 2)
                    .frame(maxWidth: 24)
            }

            HStack(spacing: 4) {
                if step.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(planColor)
                } else if step.isActive {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                }

                Text(step.label)
                    .font(.system(size: 11, weight: step.isActive ? .semibold : .regular))
                    .foregroundStyle(step.isActive ? planColor : .secondary)
            }
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    )
    }
}
