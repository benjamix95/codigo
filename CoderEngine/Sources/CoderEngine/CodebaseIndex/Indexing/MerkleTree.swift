import Foundation
import CommonCrypto

// MARK: - MerkleNode

/// A node in the Merkle tree. Leaves are files; internal nodes are directories.
/// Hash propagation: each directory hash = SHA256(sorted children hashes).
/// Change detection is O(log n): walk only branches where hashes differ.
public struct MerkleNode: Sendable, Codable, Hashable {
    /// Relative path from workspace root
    public let path: String

    /// SHA-256 hash as hex string (64 chars)
    public let hash: String

    /// true = directory, false = file
    public let isDirectory: Bool

    /// Children (only for directories)
    public let children: [MerkleNode]
}

// MARK: - MerkleTree

/// Merkle tree for efficient codebase change detection.
/// Inspired by Cursor's secure indexing: SHA-256 hash per file,
/// directory hashes derived from children, incremental sync by comparing root hashes.
///
/// Usage:
/// 1. Build tree from workspace: `MerkleTree.build(root:excludedPaths:extensions:)`
/// 2. Detect changes: `MerkleTree.diff(old:new:)` → returns changed file paths
/// 3. Derive simhash: `MerkleTree.simHash(of:)` for index reuse detection
public enum MerkleTree {

    /// Build a Merkle tree for a workspace root.
    /// Files are hashed by content (SHA-256). Directories are hashed by combining children.
    public static func build(
        root: URL,
        excludedDirs: Set<String> = defaultExcludedDirs,
        allowedExtensions: Set<String> = defaultExtensions
    ) -> MerkleNode? {
        buildNode(at: root, relativeTo: root, excludedDirs: excludedDirs, allowedExtensions: allowedExtensions)
    }

    /// Find all changed files between two Merkle trees.
    /// Returns relative paths of files that were added, removed, or modified.
    public static func diff(old: MerkleNode?, new: MerkleNode?) -> ChangeSummary {
        var added: [String] = []
        var removed: [String] = []
        var modified: [String] = []

        diffRecursive(old: old, new: new, added: &added, removed: &removed, modified: &modified)

        return ChangeSummary(added: added, removed: removed, modified: modified)
    }

    /// Compute simhash from a Merkle tree root.
    /// SimHash is a locality-sensitive hash: similar codebases produce similar hashes.
    /// Used for index reuse detection across team members (like Cursor).
    public static func simHash(of node: MerkleNode) -> UInt64 {
        // Collect all leaf hashes
        var leafHashes: [UInt64] = []
        collectLeafHashes(node, into: &leafHashes)

        guard !leafHashes.isEmpty else { return 0 }

        // SimHash algorithm: vote +1/-1 per bit position across all hashes
        var votes = [Int](repeating: 0, count: 64)
        for hash in leafHashes {
            for bit in 0..<64 {
                if (hash >> bit) & 1 == 1 {
                    votes[bit] += 1
                } else {
                    votes[bit] -= 1
                }
            }
        }

        var result: UInt64 = 0
        for bit in 0..<64 {
            if votes[bit] > 0 {
                result |= (1 << bit)
            }
        }
        return result
    }

    /// Hamming distance between two simhashes (number of differing bits).
    /// 0-3 bits: ~95%+ similarity. 4-8 bits: ~85-95%. 9+: different.
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Similarity score [0, 1] from hamming distance (64-bit hashes)
    public static func similarity(_ a: UInt64, _ b: UInt64) -> Double {
        1.0 - Double(hammingDistance(a, b)) / 64.0
    }

    // MARK: - Change Summary

    public struct ChangeSummary: Sendable {
        public let added: [String]
        public let removed: [String]
        public let modified: [String]

        public var isEmpty: Bool { added.isEmpty && removed.isEmpty && modified.isEmpty }
        public var changedPaths: [String] { added + removed + modified }
        public var totalChanges: Int { added.count + removed.count + modified.count }
    }

    // MARK: - Defaults

    public static let defaultExcludedDirs: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", ".build", "build", "Build",
        "DerivedData", "dist", "out", ".output", ".next", ".nuxt", ".cache",
        ".swiftpm", ".gradle", "__pycache__", ".pytest_cache", ".mypy_cache",
        "venv", ".venv", "env", ".env", "Pods", "Carthage", ".idea",
        ".vscode", ".vs", "vendor", "target", "coverage", ".nyc_output",
        ".terraform",
    ]

    public static let defaultExtensions: Set<String> = [
        "swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "java", "kt",
        "rb", "php", "cs", "c", "cpp", "h", "hpp", "m", "mm",
        "html", "css", "scss", "sass", "less",
        "json", "yaml", "yml", "toml", "xml", "plist",
        "md", "sh", "bash", "zsh", "sql", "graphql", "proto",
        "dart", "ex", "exs", "lua", "r", "scala", "hs", "zig",
    ]

    // MARK: - Private

    private static func buildNode(
        at url: URL,
        relativeTo root: URL,
        excludedDirs: Set<String>,
        allowedExtensions: Set<String>
    ) -> MerkleNode? {
        let fm = FileManager.default
        let path = url.path
        let relativePath = url.path.hasPrefix(root.path)
            ? String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : url.lastPathComponent

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return nil }

        if isDir.boolValue {
            let name = url.lastPathComponent
            if excludedDirs.contains(name) || name.hasPrefix(".") { return nil }

            guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else {
                return nil
            }

            let children = entries
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { buildNode(at: $0, relativeTo: root, excludedDirs: excludedDirs, allowedExtensions: allowedExtensions) }

            if children.isEmpty { return nil }

            // Directory hash = SHA256 of all children hashes concatenated
            let combined = children.map { $0.hash }.joined()
            let dirHash = sha256(combined)

            return MerkleNode(path: relativePath, hash: dirHash, isDirectory: true, children: children)
        } else {
            // File leaf — check extension
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return nil }

            // Hash file content
            guard let data = fm.contents(atPath: path) else { return nil }

            // Skip very large files (>1MB)
            guard data.count <= 1_048_576 else { return nil }

            let fileHash = sha256(data)
            return MerkleNode(path: relativePath, hash: fileHash, isDirectory: false, children: [])
        }
    }

    private static func diffRecursive(
        old: MerkleNode?,
        new: MerkleNode?,
        added: inout [String],
        removed: inout [String],
        modified: inout [String]
    ) {
        switch (old, new) {
        case (nil, let n?) where !n.isDirectory:
            added.append(n.path)
        case (nil, let n?) where n.isDirectory:
            collectLeafPaths(n, into: &added)
        case (let o?, nil) where !o.isDirectory:
            removed.append(o.path)
        case (let o?, nil) where o.isDirectory:
            collectLeafPaths(o, into: &removed)
        case (let o?, let n?):
            if o.hash == n.hash { return }  // No changes in this subtree
            if !o.isDirectory && !n.isDirectory {
                modified.append(n.path)
            } else if o.isDirectory && n.isDirectory {
                let oldMap = Dictionary(uniqueKeysWithValues: o.children.map { ($0.path, $0) })
                let newMap = Dictionary(uniqueKeysWithValues: n.children.map { ($0.path, $0) })
                let allKeys = Set(oldMap.keys).union(newMap.keys)
                for key in allKeys.sorted() {
                    diffRecursive(old: oldMap[key], new: newMap[key],
                                  added: &added, removed: &removed, modified: &modified)
                }
            } else {
                // Type changed (file→dir or dir→file)
                if let o = old { collectLeafPaths(o, into: &removed) }
                if let n = new { collectLeafPaths(n, into: &added) }
            }
        default:
            break
        }
    }

    private static func collectLeafPaths(_ node: MerkleNode, into paths: inout [String]) {
        if !node.isDirectory {
            paths.append(node.path)
        } else {
            for child in node.children {
                collectLeafPaths(child, into: &paths)
            }
        }
    }

    private static func collectLeafHashes(_ node: MerkleNode, into hashes: inout [UInt64]) {
        if !node.isDirectory {
            // Convert first 8 bytes of SHA-256 hex to UInt64
            let hex = String(node.hash.prefix(16))
            hashes.append(UInt64(hex, radix: 16) ?? 0)
        } else {
            for child in node.children {
                collectLeafHashes(child, into: &hashes)
            }
        }
    }

    // MARK: - SHA-256 helpers

    private static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
