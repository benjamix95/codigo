import Foundation
import CommonCrypto

extension MerkleTree {
    public static func build(
        indexedFiles: [IndexedFile],
        contentCache: [String: String],
        workspaceRoot: URL
    ) -> MerkleNode? {
        var fileHashes: [String: String] = [:]
        for indexed in indexedFiles {
            if let content = contentCache[indexed.absolutePath] {
                fileHashes[indexed.relativePath] = indexedSnapshotSHA256(Data(content.utf8))
                continue
            }

            guard let data = FileManager.default.contents(atPath: indexed.absolutePath) else {
                continue
            }
            fileHashes[indexed.relativePath] = indexedSnapshotSHA256(data)
        }
        guard !fileHashes.isEmpty else { return nil }
        return indexedSnapshotDirectoryNode(
            path: "",
            fileHashes: fileHashes,
            workspaceRoot: workspaceRoot
        )
    }

    private static func indexedSnapshotDirectoryNode(
        path: String,
        fileHashes: [String: String],
        workspaceRoot: URL
    ) -> MerkleNode? {
        let prefix = path.isEmpty ? "" : path + "/"
        let directFiles = fileHashes.compactMap { relativePath, hash -> MerkleNode? in
            guard relativePath.hasPrefix(prefix) else { return nil }
            let tail = String(relativePath.dropFirst(prefix.count))
            guard !tail.contains("/") else { return nil }
            return MerkleNode(path: relativePath, hash: hash, isDirectory: false, children: [])
        }

        let directDirectories = Set(
            fileHashes.keys.compactMap { relativePath -> String? in
                guard relativePath.hasPrefix(prefix) else { return nil }
                let tail = String(relativePath.dropFirst(prefix.count))
                guard let separator = tail.firstIndex(of: "/") else { return nil }
                return String(tail[..<separator])
            }
        )
        .sorted()

        let childDirectories = directDirectories.compactMap { name -> MerkleNode? in
            let childPath = path.isEmpty ? name : "\(path)/\(name)"
            return indexedSnapshotDirectoryNode(
                path: childPath,
                fileHashes: fileHashes,
                workspaceRoot: workspaceRoot
            )
        }

        let children = (directFiles + childDirectories)
            .sorted { $0.path < $1.path }
        guard !children.isEmpty else { return nil }

        let nodePath: String
        if path.isEmpty {
            nodePath = workspaceRoot.lastPathComponent
        } else {
            nodePath = path
        }
        let combined = children.map(\.hash).joined()
        return MerkleNode(
            path: nodePath,
            hash: indexedSnapshotSHA256(Data(combined.utf8)),
            isDirectory: true,
            children: children
        )
    }

    private static func indexedSnapshotSHA256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
