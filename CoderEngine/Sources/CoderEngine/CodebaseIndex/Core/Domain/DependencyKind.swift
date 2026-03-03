import Foundation

// MARK: - DependencyKind

public enum DependencyKind: String, Sendable, Codable {
    case `import`
    case inheritance
    case conformance
    case usage
}

