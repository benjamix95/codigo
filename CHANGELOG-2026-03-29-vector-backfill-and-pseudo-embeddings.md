# Changelog - 2026-03-29 - vector backfill and pseudo embeddings

## Cosa ho cambiato
- aggiunto `PseudoHashEmbeddingBackend` come fallback deterministico sempre disponibile quando CoreML e Rust FFI non sono presenti
- aggiornato `EmbeddingService` per usare davvero `pseudo_hash` invece di ritornare `nil`
- aggiunto backfill automatico del vector store alla preparazione di `semantic_search` quando l'indice semantico esiste ma `semantic_embeddings` e' vuota
- aggiunte statistiche del vector store (`embedding_row_count`, `embedding_file_count`) in `search_health_check`

## Effetto pratico
- il vector DB non resta piu' silenziosamente vuoto nei contesti dev/test o bundle incompleti
- la prima ricerca semantica utile puo' ripopolare gli embeddings senza richiedere un full reindex manuale
- la diagnostica search mostra finalmente se il ramo vettoriale ha dati reali oppure no

## Verifiche
- `CoderEngineTests/EmbeddingServiceModelsTests`
- `CoderEngineTests/UnifiedToolRuntimeTests/testSemanticSearchBackfillsVectorStoreWhenSemanticIndexExistsButTableIsEmpty`
- `CoderEngineTests/UnifiedToolRuntimeTests/testSearchHealthCheckReportsVectorAndTrigramStatus`
