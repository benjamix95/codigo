import Foundation

enum NativeDebugStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case stopped
    case error
}

struct NativeCallStackFrame: Identifiable, Codable, Hashable {
    let id: String
    let function: String
    let filePath: String
    let line: Int

    init(function: String, filePath: String, line: Int) {
        self.id = "\(function)#\(filePath)#\(line)"
        self.function = function
        self.filePath = filePath
        self.line = line
    }
}

struct NativeWatchVariable: Identifiable, Codable, Hashable {
    let id: String
    let expression: String
    let value: String

    init(expression: String, value: String) {
        self.id = expression
        self.expression = expression
        self.value = value
    }
}

struct NativeDebugSessionState: Codable, Equatable {
    static let currentPayloadVersion = 1

    var payloadVersion: Int
    var status: NativeDebugStatus
    var adapter: String
    var targetPath: String?
    var breakpointsCount: Int
    var callStack: [NativeCallStackFrame]
    var watchVariables: [NativeWatchVariable]
    var lastCommand: String?
    var lastError: String?
    var updatedAt: Date
    var metrics: DebugLifecycleMetrics

    init(
        payloadVersion: Int = currentPayloadVersion,
        status: NativeDebugStatus,
        adapter: String,
        targetPath: String?,
        breakpointsCount: Int,
        callStack: [NativeCallStackFrame],
        watchVariables: [NativeWatchVariable],
        lastCommand: String?,
        lastError: String?,
        updatedAt: Date,
        metrics: DebugLifecycleMetrics = .empty
    ) {
        self.payloadVersion = payloadVersion
        self.status = status
        self.adapter = adapter
        self.targetPath = targetPath
        self.breakpointsCount = breakpointsCount
        self.callStack = callStack
        self.watchVariables = watchVariables
        self.lastCommand = lastCommand
        self.lastError = lastError
        self.updatedAt = updatedAt
        self.metrics = metrics
    }

    static var idle: NativeDebugSessionState {
        NativeDebugSessionState(
            payloadVersion: currentPayloadVersion,
            status: .idle,
            adapter: "none",
            targetPath: nil,
            breakpointsCount: 0,
            callStack: [],
            watchVariables: [],
            lastCommand: nil,
            lastError: nil,
            updatedAt: Date(),
            metrics: .empty
        )
    }
}
