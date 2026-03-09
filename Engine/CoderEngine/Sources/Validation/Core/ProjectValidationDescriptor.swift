import Foundation

public struct ValidationTestGroup: Sendable, Codable, Equatable {
    public let id: String
    public let bundle: String
    public let pathPrefixes: [String]
    public let onlyTesting: [String]
}

public struct ProjectValidationDescriptor: Sendable, Codable, Equatable {
    public let version: Int
    public let workspace: String
    public let localScheme: String
    public let releaseScheme: String
    public let destination: String
    public let testPlan: String?
    public let codeFileGlobs: [String]
    public let excludedCodePaths: [String]
    public let securitySensitivePrefixes: [String]
    public let testGroups: [ValidationTestGroup]

    public var workspacePathComponent: String { workspace }

    public func isSecuritySensitive(path: String) -> Bool {
        securitySensitivePrefixes.contains { path.hasPrefix($0) }
    }
}
