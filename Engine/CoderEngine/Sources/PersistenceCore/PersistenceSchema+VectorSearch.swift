import Foundation

extension PersistenceSchema {
    /// pgvector extension + semantic embeddings table for vector-based search.
    /// Requires: `brew install pgvector` on the host machine.
    /// If pgvector is not available the extension creation silently fails
    /// and the HNSW index is skipped — BM25 search continues to work.
    static let vectorSearchSQL = """
    -- Tenta di abilitare pgvector. Se non disponibile (es. pg@14 senza pgvector
    -- compilato), salta silenziosamente — BM25 search continua a funzionare.
    DO $$
    BEGIN
        CREATE EXTENSION IF NOT EXISTS vector;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'pgvector not available — skipping vector search setup: %', SQLERRM;
        RETURN;
    END
    $$;

    -- Le tabelle e indici vector dipendono dall'estensione.
    -- Se pgvector non è caricato, usiamo un blocco condizionale per saltarli.
    DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
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

            CREATE INDEX IF NOT EXISTS idx_se_file_path
                ON semantic_embeddings(file_path);

            CREATE INDEX IF NOT EXISTS idx_se_content_hash
                ON semantic_embeddings(content_hash);

            CREATE INDEX IF NOT EXISTS idx_se_embedding_hnsw
                ON semantic_embeddings
                USING hnsw (embedding vector_cosine_ops)
                WITH (m = 16, ef_construction = 64);
        ELSE
            RAISE NOTICE 'pgvector extension not loaded — semantic_embeddings table skipped';
        END IF;
    END
    $$;
    """
}
