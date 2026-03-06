import Foundation

// MARK: - DebugNativeBreakpointSpec

/// Breakpoint serializzabile usato dalla debug pipeline per stage native.
public struct DebugNativeBreakpointSpec: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var filePath: String
    public var line: Int
    public var condition: String?
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        filePath: String,
        line: Int,
        condition: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.filePath = filePath
        self.line = line
        self.condition = condition
        self.isActive = isActive
    }
}
