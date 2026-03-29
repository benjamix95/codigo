# Changelog - 2026-03-29 - search routing and vector health

## Cosa ho cambiato
- corretto l'inferenza provider-side delle query senza nome tool esplicito: le query umane ora preferiscono `semantic_search`, mentre i casi regex/exact restano su `grep` e i payload web espliciti restano su `web_search`
- aggiunta una policy dedicata per evitare il grep fallback dentro `semantic_search` quando semantic index / vector index / symbol index hanno gia' risultati sufficienti
- esteso `search_health_check` con diagnostica su `vector_enabled`, `vector_db_available`, `trigram_enabled`, `embedding_backend` ed `embedding_service_available`

## Test di regressione aggiunti
- regressione su routing `query -> semantic_search`
- regressione su query naturali scoped che devono restare semantiche
- regressione su query exact/scoped che devono restare `grep`
- regressione su skip del grep fallback quando i risultati indicizzati bastano
- regressione sul payload/output di `search_health_check`

## Note operative
- il DB vettoriale non era il solo fattore: c'era anche un problema di instradamento a monte che rendeva invisibile il semantic search
- il grep fallback non e' stato rimosso: resta come safety net, ma non deve piu' pagare latenza quando l'indice ha gia' risposto bene
