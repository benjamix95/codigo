# P1 — Permessi lock file inconsistenti tra code review (0o600) e bug hunter (0o644)

## Bug Fix Record
- Categoria: B - Importante
- Bug: I lock file per code review usano `S_IRUSR | S_IWUSR` (0o600 — solo owner), mentre quelli per bug hunter usano `0o644` (world-readable). Inconsistenza senza giustificazione.
- Sintomo: Se i processi MCP girano come utenti diversi, i lock di code review falliscono mentre quelli di bug hunter funzionano.
- Impatto: Failure intermittente del locking cross-processo.
- Gravità: P1
- Strategia di fix minimo: Uniformare a `0o644` per entrambi (o `0o666` se serve world-writable).
- Commit previsto: `fix(mcp-shared-state): unify lock file permissions`
