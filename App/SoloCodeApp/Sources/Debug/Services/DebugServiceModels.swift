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
    var status: NativeDebugStatus
    var adapter: String
    var targetPath: String?
    var breakpointsCount: Int
    var callStack: [NativeCallStackFrame]
    var watchVariables: [NativeWatchVariable]
    var lastCommand: String?
    var lastError: String?
    var updatedAt: Date

    static var idle: NativeDebugSessionState {
        NativeDebugSessionState(
            status: .idle,
            adapter: "none",
            targetPath: nil,
            breakpointsCount: 0,
            callStack: [],
            watchVariables: [],
            lastCommand: nil,
            lastError: nil,
            updatedAt: Date()
        )
    }
}

