import Foundation

// MARK: - AccessLevel

/// Livello di accesso del simbolo
public enum AccessLevel: String, Sendable, Codable, Comparable {
    case `private`
    case `fileprivate`
    case `internal`
    case `public`
    case `open`

    private var sortOrder: Int {
        switch self {
        case .private: return 0
        case .fileprivate: return 1
        case .internal: return 2
        case .public: return 3
        case .open: return 4
        }
    }

    public static func < (lhs: AccessLevel, rhs: AccessLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}
