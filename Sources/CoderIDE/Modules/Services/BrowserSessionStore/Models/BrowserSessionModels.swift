import Foundation
import AppKit

// MARK: - Console & Network Models

public enum ConsoleLogLevel: String, Codable, CaseIterable {
    case log, info, warn, error, debug

    var icon: String {
        switch self {
        case .log: return "text.bubble"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .debug: return "ladybug"
        }
    }
}

public struct ConsoleLogEntry: Identifiable {
    public let id = UUID()
    public let level: ConsoleLogLevel
    public let message: String
    public let source: String?
    public let line: Int?
    public let timestamp: Date
}

public struct JSError: Identifiable {
    public let id = UUID()
    public let message: String
    public let source: String?
    public let line: Int?
    public let column: Int?
    public let stack: String?
    public let timestamp: Date
}

public struct NetworkRequest: Identifiable {
    public let id = UUID()
    public let url: String
    public let method: String
    public let status: Int?
    public let duration: Double?
    public let initiatorType: String?
    public let timestamp: Date
}

public enum BrowserEngine: String, CaseIterable {
    case wkWebView = "WKWebView"
    case cdp = "Chrome DevTools Protocol"
}

// MARK: - Bookmark & History Models

public struct BrowserBookmark: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var url: String
    public var dateAdded: Date = Date()
}

public struct BrowserHistoryEntry: Identifiable, Codable {
    public var id = UUID()
    public var title: String
    public var url: String
    public var timestamp: Date = Date()
}
