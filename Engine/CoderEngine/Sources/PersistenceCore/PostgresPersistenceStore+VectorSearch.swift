import Foundation

// MARK: - Vector Search CRUD

extension PostgresPersistenceStore {

    // MARK: - Upsert

    /// Insert or update a single chunk embedding.
    public func upsertEmbedding(_ payload: EmbeddingUpsertPayload) throws {
        let vectorLiteral = pgVectorLiteral(payload.embedding)
        let symbolsLiteral = pgTextArrayLiteral(payload.symbolNames)
        let sql = """
        INSERT INTO semantic_embeddings
            (chunk_id, file_path, content_hash, embedding, scope, kind,
             start_line, end_line, language, symbol_names, created_at, updated_at)
        VALUES (
            \(PersistenceSupport.sqlLiteral(payload.chunkId)),
            \(PersistenceSupport.sqlLiteral(payload.filePath)),
            \(payload.contentHash),
            \(vectorLiteral),
            \(PersistenceSupport.sqlLiteral(payload.scope)),
            \(PersistenceSupport.sqlLiteral(payload.kind)),
            \(payload.startLine),
            \(payload.endLine),
            \(PersistenceSupport.sqlLiteral(payload.language)),
            \(symbolsLiteral),
            NOW(), NOW()
        )
        ON CONFLICT (chunk_id) DO UPDATE SET
            file_path     = EXCLUDED.file_path,
            content_hash  = EXCLUDED.content_hash,
            embedding     = EXCLUDED.embedding,
            scope         = EXCLUDED.scope,
            kind          = EXCLUDED.kind,
            start_line    = EXCLUDED.start_line,
            end_line      = EXCLUDED.end_line,
            language      = EXCLUDED.language,
            symbol_names  = EXCLUDED.symbol_names,
            updated_at    = NOW();
        """
        _ = try execute(sql: sql)
    }

    /// Batch upsert multiple embeddings in a single transaction.
    public func upsertEmbeddingsBatch(_ payloads: [EmbeddingUpsertPayload]) throws {
        guard !payloads.isEmpty else { return }

        var sqlParts: [String] = ["BEGIN;"]
        for payload in payloads {
            let vectorLiteral = pgVectorLiteral(payload.embedding)
            let symbolsLiteral = pgTextArrayLiteral(payload.symbolNames)
            sqlParts.append("""
            INSERT INTO semantic_embeddings
                (chunk_id, file_path, content_hash, embedding, scope, kind,
                 start_line, end_line, language, symbol_names, created_at, updated_at)
            VALUES (
                \(PersistenceSupport.sqlLiteral(payload.chunkId)),
                \(PersistenceSupport.sqlLiteral(payload.filePath)),
                \(payload.contentHash),
                \(vectorLiteral),
                \(PersistenceSupport.sqlLiteral(payload.scope)),
                \(PersistenceSupport.sqlLiteral(payload.kind)),
                \(payload.startLine),
                \(payload.endLine),
                \(PersistenceSupport.sqlLiteral(payload.language)),
                \(symbolsLiteral),
                NOW(), NOW()
            )
            ON CONFLICT (chunk_id) DO UPDATE SET
                file_path     = EXCLUDED.file_path,
                content_hash  = EXCLUDED.content_hash,
                embedding     = EXCLUDED.embedding,
                scope         = EXCLUDED.scope,
                kind          = EXCLUDED.kind,
                start_line    = EXCLUDED.start_line,
                end_line      = EXCLUDED.end_line,
                language      = EXCLUDED.language,
                symbol_names  = EXCLUDED.symbol_names,
                updated_at    = NOW();
            """)
        }
        sqlParts.append("COMMIT;")
        _ = try execute(sql: sqlParts.joined(separator: "\n"))
    }

    // MARK: - Delete

    /// Remove all embeddings for a given file (used during re-index).
    public func deleteEmbeddingsForFile(_ filePath: String) throws {
        let sql = """
        DELETE FROM semantic_embeddings
        WHERE file_path = \(PersistenceSupport.sqlLiteral(filePath));
        """
        _ = try execute(sql: sql)
    }

    /// Remove embeddings for specific chunk IDs.
    public func deleteEmbeddings(chunkIds: [String]) throws {
        guard !chunkIds.isEmpty else { return }
        let inList = chunkIds.map { PersistenceSupport.sqlLiteral($0) }.joined(separator: ", ")
        let sql = """
        DELETE FROM semantic_embeddings WHERE chunk_id IN (\(inList));
        """
        _ = try execute(sql: sql)
    }

    // MARK: - Vector Search

    /// Find the top-K nearest chunks by cosine similarity.
    /// Returns results with similarity ≥ `threshold` (0..1).
    public func vectorSearch(
        queryEmbedding: [Float],
        limit: Int = 25,
        threshold: Double = 0.3
    ) throws -> [VectorSearchHit] {
        let vectorLiteral = pgVectorLiteral(queryEmbedding)
        // pgvector <=> returns cosine distance in [0, 2].
        // similarity = 1 - distance/2  maps to [0, 1].
        let minDistance = (1.0 - threshold) * 2.0
        let sql = """
        SELECT
            chunk_id,
            file_path,
            1.0 - (embedding <=> \(vectorLiteral)) / 2.0 AS similarity,
            start_line,
            end_line,
            scope,
            kind,
            language,
            symbol_names
        FROM semantic_embeddings
        WHERE (embedding <=> \(vectorLiteral)) <= \(minDistance)
        ORDER BY embedding <=> \(vectorLiteral)
        LIMIT \(limit);
        """
        let raw = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        return parseVectorSearchRows(raw)
    }

    // MARK: - Lookup existing embeddings

    /// Return chunk IDs and content hashes for a file (for incremental re-index).
    public func embeddedChunkRecords(forFile filePath: String) throws -> [EmbeddingRecord] {
        let sql = """
        SELECT chunk_id, content_hash
        FROM semantic_embeddings
        WHERE file_path = \(PersistenceSupport.sqlLiteral(filePath));
        """
        let raw = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        return parseEmbeddingRecordRows(raw)
    }

    /// Check if the vector search table exists and pgvector is available.
    public func isVectorSearchAvailable() throws -> Bool {
        let sql = """
        SELECT EXISTS (
            SELECT 1 FROM pg_extension WHERE extname = 'vector'
        );
        """
        let result = try execute(sql: sql).trimmingCharacters(in: .whitespacesAndNewlines)
        return result == "t"
    }

    // MARK: - Private Helpers

    /// Format a Float array as a pgvector literal: '[0.1,0.2,...]'
    private func pgVectorLiteral(_ vector: [Float]) -> String {
        let csv = vector.map { String(format: "%.6f", $0) }.joined(separator: ",")
        return "'[\(csv)]'"
    }

    /// Format a Swift string array as a Postgres TEXT[] literal.
    private func pgTextArrayLiteral(_ values: [String]) -> String {
        guard !values.isEmpty else { return "'{}'::TEXT[]" }
        let escaped = values.map {
            "\"" + $0.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "'{" + escaped.joined(separator: ",") + "}'::TEXT[]"
    }

    /// Parse psql tab-separated output rows into VectorSearchHit array.
    private func parseVectorSearchRows(_ raw: String) -> [VectorSearchHit] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line in
            let cols = line.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard cols.count >= 9 else { return nil }
            let symbolsRaw = cols[8]
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
            let symbols = symbolsRaw.isEmpty ? [String]() :
                symbolsRaw.components(separatedBy: ",").map {
                    $0.trimmingCharacters(in: .init(charactersIn: " \""))
                }
            return VectorSearchHit(
                id: cols[0],
                filePath: cols[1],
                score: Double(cols[2]) ?? 0,
                startLine: Int(cols[3]) ?? 0,
                endLine: Int(cols[4]) ?? 0,
                scope: cols[5],
                kind: cols[6],
                language: cols[7],
                symbolNames: symbols
            )
        }
    }

    /// Parse psql output for embedding records.
    private func parseEmbeddingRecordRows(_ raw: String) -> [EmbeddingRecord] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line in
            let cols = line.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard cols.count >= 2 else { return nil }
            return EmbeddingRecord(
                chunkId: cols[0],
                contentHash: UInt64(cols[1]) ?? 0
            )
        }
    }
}
