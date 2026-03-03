import SwiftUI

extension SwarmPanelView {
    // MARK: - Helpers

    func panelRoleDisplayName(from swarmId: String) -> String {
        let id = swarmId
        if let dashRange = id.range(of: "-", options: .backwards),
           id[dashRange.upperBound...].count <= 10,
           id[dashRange.upperBound...].allSatisfy({ $0.isHexDigit || $0.isLetter }) {
            return String(id[..<dashRange.lowerBound]).capitalized
        }
        return id.capitalized
    }

    func panelStatusAccent(for status: SwarmCardStatus) -> Color {
        switch status {
        case .running:
            return DesignSystem.Colors.swarmColor
        case .completed:
            return DesignSystem.Colors.success
        case .failed:
            return DesignSystem.Colors.error
        case .idle:
            return .secondary
        }
    }

    func stepIcon(_ step: SwarmStep) -> String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.right.circle.fill"
        case .pending: return "circle"
        }
    }

    func stepColor(_ step: SwarmStep) -> Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success
        case .inProgress: return DesignSystem.Colors.warning
        case .pending: return DesignSystem.Colors.borderAccent
        }
    }

    func hasRawDetail(_ activity: TaskActivity) -> Bool {
        !(activity.payload["output"] ?? "").isEmpty ||
        !(activity.payload["stderr"] ?? "").isEmpty ||
        !(activity.payload["cwd"] ?? "").isEmpty ||
        !(activity.payload["diffPreview"] ?? "").isEmpty
    }

    func liveSubtitle(for card: SwarmLiveCardState) -> String? {
        let last = card.recentEvents.last
        let candidates: [String?] = [
            card.currentDetail,
            last?.detail,
            last?.payload["detail"],
            last?.payload["query"],
            last?.payload["path"],
            last?.payload["command"],
            last?.payload["tool"],
            last?.payload["mcp_tool"],
        ]
        for candidate in candidates {
            let text = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            if lower == "started" || lower == "running" || lower == "in_progress" || lower == "pending" {
                continue
            }
            return String(text.prefix(120))
        }
        return nil
    }

    func rawDetail(for activity: TaskActivity) -> String {
        var lines: [String] = []
        if let cwd = activity.payload["cwd"], !cwd.isEmpty { lines.append("cwd: \(cwd)") }
        if let output = activity.payload["output"], !output.isEmpty {
            lines.append(String(output.prefix(4096)))
        }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty {
            lines.append("stderr:\n\(String(stderr.prefix(4096)))")
        }
        if let diff = activity.payload["diffPreview"], !diff.isEmpty {
            lines.append("diff:\n\(String(diff.prefix(2048)))")
        }
        return lines.joined(separator: "\n\n")
    }
}
