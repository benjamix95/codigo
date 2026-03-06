import CoderEngine
import Foundation

struct DebugNativePipelineTaskContext {
    let stage: DebugStageKind
    let backendPolicy: DebugBackendPolicy
    let targetPath: String?
    let arguments: [String]
    let breakpoints: [DebugNativeBreakpointSpec]
    let watchExpressions: [String]

    init?(task: TaskNode) {
        guard let stage = task.debugStage, stage.isNativeStage else {
            return nil
        }
        self.stage = stage
        self.backendPolicy = DebugBackendPolicy(
            rawValue: task.metadata["backend_policy"] ?? ""
        ) ?? .hybrid

        let rawTargetPath = task.metadata["target_path"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.targetPath = rawTargetPath?.isEmpty == true ? nil : rawTargetPath
        self.arguments = Self.parseList(task.metadata["arguments"])
        self.watchExpressions = Self.parseList(task.metadata["watch_expressions"])
        self.breakpoints = Self.parseBreakpoints(task.metadata["native_breakpoints_json"])
    }

    var debugBreakpoints: [DebugBreakpoint] {
        breakpoints.map(DebugBreakpoint.init(spec:))
    }

    private static func parseList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseBreakpoints(_ raw: String?) -> [DebugNativeBreakpointSpec] {
        guard let raw,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([DebugNativeBreakpointSpec].self, from: data) else {
            return []
        }
        return decoded
    }
}

struct DebugNativeBackendLog {
    let severity: DebugEntrySeverity
    let source: String
    let message: String
    let detail: String?
    let category: String?
}

struct DebugNativeBackendOutcome {
    var state: NativeDebugSessionState?
    var logs: [DebugNativeBackendLog]

    init(
        state: NativeDebugSessionState? = nil,
        logs: [DebugNativeBackendLog] = []
    ) {
        self.state = state
        self.logs = logs
    }
}

extension DebugBreakpoint {
    init(spec: DebugNativeBreakpointSpec) {
        self.id = UUID(uuidString: spec.id) ?? UUID()
        self.filePath = spec.filePath
        self.line = spec.line
        self.condition = spec.condition
        self.isActive = spec.isActive
    }

    var pipelineSpec: DebugNativeBreakpointSpec {
        DebugNativeBreakpointSpec(
            id: id.uuidString,
            filePath: filePath,
            line: line,
            condition: condition,
            isActive: isActive
        )
    }
}

extension Array where Element == DebugBreakpoint {
    var pipelineSpecs: [DebugNativeBreakpointSpec] {
        map(\.pipelineSpec)
    }
}
