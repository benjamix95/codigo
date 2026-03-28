# Changelog 2026-03-29 - Plan runtime routing e preservazione metadati pipeline chat

- Corretto `apply_plan_runtime_action` in Rust: quando manca `runtime_snapshot`, la `conversation_id` esplicita della request ora prevale su una `selected_conversation_id` stale.
- Aggiunta regressione Rust per verificare che il seed del runtime plan nasca sulla conversazione richiesta e che il path `missing_conversation_for_plan` resti coperto.
- Corretto il sync locale Swift del messaggio assistant dopo `sync_assistant_pipeline_state`: i metadati locali vengono ora preservati sia quando il messaggio viene sostituito dal payload pipeline, sia quando resta la versione post-commit Rust.
- Aggiunta regressione Swift per verificare che il commit pipeline mantenga i metadati assistant locali e che la propagazione dei `toolMarker` resti intatta.
- La parte NDJSON non e' stata toccata per esplicita richiesta di scope.
