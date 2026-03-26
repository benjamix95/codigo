import CoderEngine
import Foundation

/// Costruisce un report Markdown da uno snapshot di sessione review.
enum ReviewPanelReportMarkdownBuilder {
    static func markdown(
        snapshot: CodeReviewSessionSnapshot,
        scopeLabel: String,
        scanDepthLabel: String,
        completedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: completedAt)

        var lines: [String] = []
        lines.append("# Code review report")
        lines.append("")
        lines.append("- **Session**: `\(snapshot.sessionId)`")
        lines.append("- **Scope**: \(scopeLabel)")
        lines.append("- **Scan depth**: \(scanDepthLabel)")
        lines.append("- **Generated**: \(stamp)")
        lines.append("- **Phase**: \(snapshot.phase.rawValue)")
        if let err = snapshot.lastError, !err.isEmpty {
            lines.append("- **Last error**: \(err)")
        }
        lines.append("")

        let items = snapshot.findings.sorted { $0.filePath < $1.filePath }
        if items.isEmpty {
            lines.append("## Findings")
            lines.append("")
            lines.append("_Nessun finding in snapshot._")
        } else {
            lines.append("## Findings (\(items.count))")
            lines.append("")
            for f in items {
                let status = statusLine(for: f.status)
                let lineTag = f.lineNumber.map { String($0) } ?? "—"
                lines.append("### \(f.severity.rawValue.capitalized) · \(f.filePath):\(lineTag)")
                lines.append("")
                lines.append(f.message)
                lines.append("")
                lines.append("- **Stato**: \(status)")
                if let fix = f.suggestedFix, !fix.isEmpty {
                    lines.append("- **Fix suggerita**:")
                    lines.append("```text")
                    lines.append(fix)
                    lines.append("```")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func statusLine(for status: FindingStatus) -> String {
        switch status {
        case .open: return "Solo trovato (aperto)"
        case .fixApplied, .patchApplied, .merged: return "Risolto / applicato"
        case .patchPreparing, .patchReady, .patchApplying: return "In lavorazione patch"
        case .patchFailed, .blocked: return "Bloccato / patch fallita"
        case .prOpened: return "PR aperta"
        case .dismissed, .wontFix: return "Ignorato"
        case .closed: return "Chiuso"
        }
    }
}
