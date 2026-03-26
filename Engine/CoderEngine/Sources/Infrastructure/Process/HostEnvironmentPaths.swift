import Foundation

// MARK: - HostEnvironmentPaths

/// Directory standard dove Homebrew installa binari (`rg`, `psql`, …).
/// Utile perché app GUI e subprocess spesso hanno un PATH minimale senza queste entry.
public enum HostEnvironmentPaths {

    public static let homebrewBinaryDirectories: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// Antepone le directory Homebrew esistenti al `PATH` se assenti, così subprocess (MCP, CLI) trovano `rg`.
    public static func augmentedPATH(existing: String?) -> String {
        let current = existing ?? ""
        var segments = current.split(separator: ":").map(String.init).filter { !$0.isEmpty }
        var seen = Set(segments)
        var prefix: [String] = []
        for dir in homebrewBinaryDirectories {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            if seen.insert(dir).inserted {
                prefix.append(dir)
            }
        }
        if prefix.isEmpty {
            return current.isEmpty ? fallbackSystemPATH : current
        }
        return (prefix + segments).joined(separator: ":")
    }

    private static var fallbackSystemPATH: String {
        "/usr/bin:/bin:/usr/sbin:/sbin"
    }
}
