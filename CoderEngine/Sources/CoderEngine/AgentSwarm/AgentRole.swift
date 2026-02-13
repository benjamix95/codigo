import Foundation

/// Ruoli specializzati nel swarm di agenti
public enum AgentRole: String, CaseIterable, Codable, Sendable {
    case planner
    case coder
    case debugger
    case reviewer
    case docWriter
    case securityAuditor
    case testWriter

    /// Nome visualizzato per la UI
    public var displayName: String {
        switch self {
        case .planner: return "Planner"
        case .coder: return "Coder"
        case .debugger: return "Debugger"
        case .reviewer: return "Reviewer"
        case .docWriter: return "DocWriter"
        case .securityAuditor: return "SecurityAuditor"
        case .testWriter: return "TestWriter"
        }
    }
}
