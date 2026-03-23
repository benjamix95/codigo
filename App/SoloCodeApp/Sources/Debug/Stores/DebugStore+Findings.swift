import Foundation

// MARK: - Debug Finding Model

struct DebugFinding: Identifiable, Equatable, Codable {
    let id: UUID
    let title: String
    let filePath: String?
    let lineNumber: Int?
    let severity: DebugFindingSeverity
    let hypothesisId: String?
    var status: DebugFindingStatus
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        filePath: String? = nil,
        lineNumber: Int? = nil,
        severity: DebugFindingSeverity = .medium,
        hypothesisId: String? = nil,
        status: DebugFindingStatus = .open,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.severity = severity
        self.hypothesisId = hypothesisId
        self.status = status
        self.createdAt = createdAt
    }
}

enum DebugFindingSeverity: String, Equatable, Codable {
    case critical
    case high
    case medium
    case low
    case info

    var icon: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .high:     return "exclamationmark.triangle.fill"
        case .medium:   return "exclamationmark.triangle"
        case .low:      return "info.circle"
        case .info:     return "info.circle.fill"
        }
    }
}

enum DebugFindingStatus: String, Equatable, Codable {
    case open
    case investigating
    case fixed
    case dismissed
}

// MARK: - DebugStore Extensions

extension DebugStore {
    /// Number of open (non-fixed, non-dismissed) findings.
    var openFindingsCount: Int {
        debugFindings.filter { $0.status == .open || $0.status == .investigating }.count
    }

    /// Adds a finding from a confirmed hypothesis.
    func addFinding(fromHypothesis hypothesis: DebugHypothesis) {
        let finding = DebugFinding(
            title: hypothesis.title,
            filePath: hypothesis.relatedFiles.first,
            severity: .high,
            hypothesisId: hypothesis.id.uuidString,
            status: .investigating
        )
        debugFindings.append(finding)
    }

    /// Adds a finding from a debug marker (file reference).
    func addFinding(fromMarker marker: DebugMarker) {
        let finding = DebugFinding(
            title: marker.markerComment,
            filePath: marker.filePath,
            lineNumber: marker.lineNumber,
            severity: .medium,
            status: .open
        )
        debugFindings.append(finding)
    }

    /// Adds a resolution summary finding.
    func addResolutionSummaryFinding(summary: String) {
        let finding = DebugFinding(
            title: "Resolved: \(String(summary.prefix(80)))",
            severity: .info,
            status: .fixed
        )
        debugFindings.append(finding)
    }

    /// Updates finding status by ID.
    @discardableResult
    func updateFindingStatus(id: UUID, status: DebugFindingStatus) -> Bool {
        guard let index = debugFindings.firstIndex(where: { $0.id == id }) else { return false }
        debugFindings[index].status = status
        return true
    }
}
