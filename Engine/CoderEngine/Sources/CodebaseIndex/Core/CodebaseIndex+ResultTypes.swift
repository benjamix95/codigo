import Foundation

// MARK: - Result Types

/// Indexing result
public struct IndexResult: Sendable {
    public let totalFiles: Int
    public let totalSourceFiles: Int
    public let totalSymbols: Int
    public let totalDirectories: Int
    public let durationMs: Int
    public let languages: [FileLanguage: Int]
    public let updatedFiles: Int

    public init(
        totalFiles: Int,
        totalSourceFiles: Int,
        totalSymbols: Int,
        totalDirectories: Int,
        durationMs: Int,
        languages: [FileLanguage: Int],
        updatedFiles: Int = 0
    ) {
        self.totalFiles = totalFiles
        self.totalSourceFiles = totalSourceFiles
        self.totalSymbols = totalSymbols
        self.totalDirectories = totalDirectories
        self.durationMs = durationMs
        self.languages = languages
        self.updatedFiles = updatedFiles
    }

    /// Text summary
    public var summary: String {
        var lines: [String] = []
        lines.append("✅ Index complete in \(durationMs)ms")
        lines.append("  Files: \(totalFiles) total, \(totalSourceFiles) source")
        lines.append("  Directories: \(totalDirectories)")
        lines.append("  Symbols: \(totalSymbols)")
        if updatedFiles > 0 {
            lines.append("  Updated: \(updatedFiles) files")
        }
        if !languages.isEmpty {
            let sorted = languages.sorted { $0.value > $1.value }
            lines.append(
                "  Languages: "
                    + sorted.prefix(8).map { "\($0.key.rawValue)(\($0.value))" }.joined(
                        separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Index status
public enum IndexStatus: String, Sendable {
    case idle
    case indexing
    case ready
    case error
}

/// Index status information
public struct IndexStatusInfo: Sendable {
    public let status: IndexStatus
    public let totalFiles: Int
    public let totalSourceFiles: Int
    public let totalSymbols: Int
    public let lastIndexedAt: Date?
    public let indexDurationMs: Int
    public let workspacePaths: [String]
    public let progress: IndexingProgress?
}

/// Progress information during indexing
public struct IndexingProgress: Sendable {
    public let current: Int
    public let total: Int
    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }
    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    public var percentText: String {
        "\(Int(fraction * 100))%"
    }
}
