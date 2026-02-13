import Foundation

/// Partizione del codebase assegnata a uno swarm
public struct CodebasePartition: Sendable {
    public let id: String
    public let paths: [String]

    public init(id: String, paths: [String]) {
        self.id = id
        self.paths = paths
    }
}

/// Strategia di partizionamento
public enum PartitionStrategy: String, Sendable {
    /// Ogni sottodirectory principale = 1 partizione
    case directory = "directory"
    /// Distribuisce file per avere ~uguale numero per partizione
    case balanced = "balanced"
}

/// Divide il codebase in partizioni per analisi multi-swarm
public enum CodebasePartitioner: Sendable {
    /// Crea N partizioni del workspace
    public static func partition(
        workspacePath: URL,
        count: Int,
        strategy: PartitionStrategy = .directory,
        excludedPaths: [String] = []
    ) -> [CodebasePartition] {
        let files = WorkspaceScanner.listSourceFiles(workspacePath: workspacePath, excludedPaths: excludedPaths)
        guard !files.isEmpty else {
            return [CodebasePartition(id: "p0", paths: [])]
        }

        switch strategy {
        case .directory:
            return partitionByDirectory(files: files, maxPartitions: count)
        case .balanced:
            return partitionBalanced(files: files, count: count)
        }
    }

    /// Raggruppa per directory principale (primo componente del path)
    private static func partitionByDirectory(files: [String], maxPartitions: Int) -> [CodebasePartition] {
        var byDir: [String: [String]] = [:]
        for path in files {
            let parts = path.split(separator: "/")
            let root = parts.count > 1 ? String(parts[0]) : "_root"
            byDir[root, default: []].append(path)
        }

        let dirs = byDir.keys.sorted()
        var result: [CodebasePartition] = []
        for (i, dir) in dirs.enumerated() {
            let id = "p\(i)"
            let paths = byDir[dir] ?? []
            result.append(CodebasePartition(id: id, paths: paths))
        }

        if result.count > maxPartitions {
            return mergePartitions(result, targetCount: maxPartitions)
        }
        if result.isEmpty {
            return [CodebasePartition(id: "p0", paths: files)]
        }
        return result
    }

    /// Distribuisce file in modo bilanciato
    private static func partitionBalanced(files: [String], count: Int) -> [CodebasePartition] {
        let n = min(count, files.count)
        let chunkSize = (files.count + n - 1) / n
        var result: [CodebasePartition] = []
        for i in 0..<n {
            let start = i * chunkSize
            let end = min(start + chunkSize, files.count)
            guard start < end else { continue }
            let slice = Array(files[start..<end])
            result.append(CodebasePartition(id: "p\(i)", paths: slice))
        }
        return result.isEmpty ? [CodebasePartition(id: "p0", paths: files)] : result
    }

    private static func mergePartitions(_ partitions: [CodebasePartition], targetCount: Int) -> [CodebasePartition] {
        guard partitions.count > targetCount else { return partitions }
        var merged: [CodebasePartition] = []
        let perMerge = (partitions.count + targetCount - 1) / targetCount
        for i in stride(from: 0, to: partitions.count, by: perMerge) {
            let slice = Array(partitions[i..<min(i + perMerge, partitions.count)])
            let allPaths = slice.flatMap(\.paths)
            merged.append(CodebasePartition(id: "p\(merged.count)", paths: allPaths))
        }
        return merged
    }
}
