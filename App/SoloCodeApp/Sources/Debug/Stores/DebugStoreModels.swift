import SwiftUI

// MARK: - Debug Flow Phase (linear: Describe → Reproduce → Fix → Verify → Resolve)

enum DebugFlowPhase: String, Equatable, CaseIterable {
    case idle
    // Phase 1: DESCRIBE THE BUG — Agent reads logs, errors, stack traces, gathers context
    case describing
    // Phase 2: REPRODUCE THE BUG — Agent adds instrumentation, user reproduces
    case reproducing
    // Phase 3: FIX — Agent hypothesizes, instruments, observes, fixes
    case fixing
    // Sub-phase of fixing: agent is actively inserting instrumentation (logging, asserts)
    case instrumenting
    // Phase 4: VERIFY THE FIX — Agent runs tests, checks for regressions
    case verifying
    // Terminal: Bug resolved
    case resolved

    /// Main linear phases for the progress bar.
    static var mainPhases: [DebugFlowPhase] { [.describing, .reproducing, .fixing, .verifying, .resolved] }

    /// Human-readable label for each phase
    var label: String {
        switch self {
        case .idle:          return ""
        case .describing:    return "Describe the Bug"
        case .reproducing:   return "Reproduce"
        case .fixing:        return "Fix"
        case .instrumenting: return "Instrumenting"
        case .verifying:     return "Verify the Fix"
        case .resolved:      return "Resolved"
        }
    }

    /// The main phase this sub-phase belongs to (for progress bar highlighting)
    var mainPhase: DebugFlowPhase {
        switch self {
        case .instrumenting: return .fixing
        default:             return self
        }
    }

    /// Phase index for progress bar (0-based among mainPhases)
    var phaseIndex: Int {
        DebugFlowPhase.mainPhases.firstIndex(of: mainPhase) ?? 0
    }

    /// Is this phase active (not idle, not resolved)?
    var isActive: Bool {
        self != .idle && self != .resolved
    }
}

/// Tracks a debug marker inserted by the agent into a source file
struct DebugMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let filePath: String
    let lineNumber: Int          // line where marker was inserted
    let markerComment: String    // e.g. "// 🐛 DEBUG: ..."
    let originalContent: String? // original line content for clean revert
    let insertedAt: Date

    init(filePath: String, lineNumber: Int, markerComment: String, originalContent: String? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.markerComment = markerComment
        self.originalContent = originalContent
        self.insertedAt = Date()
    }
}

// MARK: - Debug Entry Types

enum DebugEntrySeverity: String, Codable, CaseIterable {
    case error, warning, info, verbose, trace
    var icon: String {
        switch self {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        case .verbose: return "text.alignleft"
        case .trace:   return "waveform"
        }
    }
    var color: Color {
        switch self {
        case .error:   return DesignSystem.Colors.error
        case .warning: return DesignSystem.Colors.warning
        case .info:    return DesignSystem.Colors.info
        case .verbose: return .secondary
        case .trace:   return .secondary.opacity(0.6)
        }
    }
}

struct DebugLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let severity: DebugEntrySeverity
    let source: String        // file:line or module name
    let message: String
    let detail: String?       // stack trace, extra context
    let category: String?     // "compiler", "runtime", "test", "network", "custom"

    init(severity: DebugEntrySeverity, source: String, message: String, detail: String? = nil, category: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.severity = severity
        self.source = source
        self.message = message
        self.detail = detail
        self.category = category
    }
}

struct DebugHypothesis: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    var status: HypothesisStatus
    var evidence: [String]      // supporting evidence collected
    let createdAt: Date

    enum HypothesisStatus: String, Codable {
        case proposed, investigating, confirmed, rejected
        var icon: String {
            switch self {
            case .proposed:      return "lightbulb.fill"
            case .investigating: return "magnifyingglass"
            case .confirmed:     return "checkmark.circle.fill"
            case .rejected:      return "xmark.circle"
            }
        }
        var color: Color {
            switch self {
            case .proposed:      return DesignSystem.Colors.warning
            case .investigating: return DesignSystem.Colors.info
            case .confirmed:     return DesignSystem.Colors.success
            case .rejected:      return .secondary
            }
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        status: HypothesisStatus = .proposed,
        evidence: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

/// Runtime log entry collected from .codigo/debug.log (Cursor-style JSONL).
/// Captures variable states, execution paths, timing — written by agent instrumentation.
struct RuntimeLogEntry: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let location: String          // file:line where the log was emitted
    let message: String
    let data: [String: String]    // arbitrary key-value data (variable values, timing, etc.)
    let sessionId: String?
    let runId: String?            // groups logs from a single reproduce run
    let hypothesisId: String?     // links to the hypothesis this log supports

    init(
        location: String,
        message: String,
        data: [String: String] = [:],
        sessionId: String? = nil,
        runId: String? = nil,
        hypothesisId: String? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.location = location
        self.message = message
        self.data = data
        self.sessionId = sessionId
        self.runId = runId
        self.hypothesisId = hypothesisId
    }
}

/// Tracks an instrumentation point the agent inserted (logging, assert, timing).
/// Richer than DebugMarker — includes hypothesisId and type.
struct InstrumentationPoint: Identifiable, Codable, Equatable {
    let id: UUID
    let filePath: String
    let lineNumber: Int
    let type: InstrumentationType
    let code: String               // the instrumentation code inserted
    let hypothesisId: String?      // which hypothesis this instruments
    let insertedAt: Date

    enum InstrumentationType: String, Codable, Equatable {
        case logging      // print/NSLog/os_log
        case assertion     // assert/precondition
        case timing        // timing measurement
        case variable      // variable state capture
    }

    init(filePath: String, lineNumber: Int, type: InstrumentationType, code: String, hypothesisId: String? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.type = type
        self.code = code
        self.hypothesisId = hypothesisId
        self.insertedAt = Date()
    }
}

struct DebugBreakpoint: Identifiable, Codable {
    let id: UUID
    let filePath: String
    let line: Int
    let condition: String?
    var isActive: Bool

    init(filePath: String, line: Int, condition: String? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.line = line
        self.condition = condition
        self.isActive = true
    }
}

