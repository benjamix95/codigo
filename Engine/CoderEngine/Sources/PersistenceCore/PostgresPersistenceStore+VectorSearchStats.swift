import Foundation

public struct VectorSearchTableStats: Sendable, Equatable {
    public let rowCount: Int
    public let fileCount: Int

    public init(rowCount: Int, fileCount: Int) {
        self.rowCount = rowCount
        self.fileCount = fileCount
    }
}

extension PostgresPersistenceStore {
    public func vectorSearchTableStats() throws -> VectorSearchTableStats {
        guard try isVectorSearchAvailable() else {
            return VectorSearchTableStats(rowCount: 0, fileCount: 0)
        }

        let sql = """
        SELECT COUNT(*)::TEXT || '|' || COUNT(DISTINCT file_path)::TEXT
        FROM semantic_embeddings;
        """
        let raw = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.components(separatedBy: "|")
        let rowCount = Int(parts.first ?? "") ?? 0
        let fileCount = Int(parts.dropFirst().first ?? "") ?? 0
        return VectorSearchTableStats(rowCount: rowCount, fileCount: fileCount)
    }

    func vectorSearchRowCount(forFiles filePaths: [String]) throws -> Int {
        guard !filePaths.isEmpty else { return 0 }
        guard try isVectorSearchAvailable() else { return 0 }
        let inList = filePaths.map { PersistenceSupport.sqlLiteral($0) }.joined(separator: ", ")
        let sql = """
        SELECT COUNT(*)
        FROM semantic_embeddings
        WHERE file_path IN (\(inList));
        """
        let raw = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(raw) ?? 0
    }

    func deleteAllEmbeddings() throws {
        guard try isVectorSearchAvailable() else { return }
        let sql = """
        TRUNCATE TABLE semantic_embeddings;
        """
        _ = try execute(sql: sql)
    }
}
