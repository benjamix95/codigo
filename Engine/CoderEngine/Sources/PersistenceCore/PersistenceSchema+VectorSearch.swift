import Foundation

extension PersistenceSchema {
    /// pgvector extension + semantic embeddings table for vector-based search.
    /// Requires: `brew install pgvector` on the host machine.
    /// If pgvector is not available the extension creation silently fails
    /// and the HNSW index is skipped — BM25 search continues to work.
    static let vectorSearchSQL = """
    -- Enable pgvector (idempotent; no-op if already loaded)
    CREATE EXTENSION IF NOT EXISTS vector;

    -- Chunk embeddings produced by the local CoreML / ONNX pipeline.
    CREATE TABLE IF NOT EXISTS semantic_embeddings (
        chunk_id        TEXT PRIMARY KEY,
        file_path       TEXT NOT NULL,
        content_hash    BIGINT NOT NULL,
        embedding       vector(384) NOT NULL,
        scope           TEXT NOT NULL DEFAULT '',
        kind            TEXT NOT NULL DEFAULT '',
        start_line      INTEGER NOT NULL DEFAULT 0,
        end_line        INTEGER NOT NULL DEFAULT 0,
        language        TEXT NOT NULL DEFAULT '',
        symbol_names    TEXT[] DEFAULT '{}',
        created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Fast file-level operations (delete old chunks, incremental re-index).
    CREATE INDEX IF NOT EXISTS idx_se_file_path
        ON semantic_embeddings(file_path);

    -- Skip re-embedding when content hasn't changed.
    CREATE INDEX IF NOT EXISTS idx_se_content_hash
        ON semantic_embeddings(content_hash);

    -- HNSW index for sub-10 ms approximate nearest-neighbour queries.
    -- m = 16  (connections per layer — good balance for 384-dim)
    -- ef_construction = 64  (build-time search depth)
    CREATE INDEX IF NOT EXISTS idx_se_embedding_hnsw
        ON semantic_embeddings
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64);
    """
}
