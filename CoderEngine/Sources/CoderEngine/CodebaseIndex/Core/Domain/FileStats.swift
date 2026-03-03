import Foundation

// MARK: - FileStats

/// Statistiche aggregate dell'indice
public struct FileStats: Sendable {
    public let totalFiles: Int
    public let totalDirectories: Int
    public let totalSize: UInt64
    public let languageBreakdown: [FileLanguage: Int]
    public let largestFiles: [(path: String, size: UInt64)]
    public let deepestPath: (path: String, depth: Int)?

    public init(
        totalFiles: Int,
        totalDirectories: Int,
        totalSize: UInt64,
        languageBreakdown: [FileLanguage: Int],
        largestFiles: [(path: String, size: UInt64)] = [],
        deepestPath: (path: String, depth: Int)? = nil
    ) {
        self.totalFiles = totalFiles
        self.totalDirectories = totalDirectories
        self.totalSize = totalSize
        self.languageBreakdown = languageBreakdown
        self.largestFiles = largestFiles
        self.deepestPath = deepestPath
    }

    public var summary: String {
        var lines: [String] = []
        lines.append("Files: \(totalFiles)")
        lines.append("Directories: \(totalDirectories)")
        lines.append("Size: \(totalSize) bytes")
        if !languageBreakdown.isEmpty {
            let topLanguages = languageBreakdown
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { "\($0.key.rawValue): \($0.value)" }
                .joined(separator: ", ")
            lines.append("Languages: \(topLanguages)")
        }
        return lines.joined(separator: "\n")
    }
}
