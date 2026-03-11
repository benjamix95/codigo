# P2 — Mancano ancora benchmark dedicati per queue MCP e roundtrip tool Rust

## Bug Fix Record
- Categoria: B
- Bug: la nuova tranche MCP/shared-state sposta logica in Rust, ma il benchmark suite non misura ancora queue claim, rendering tool e roundtrip MCP.
- Sintomo: non esistono metriche dedicate per `mcp_tool_roundtrip`, `command_queue_claim` o `shared_state_read`.
- Impatto: la correttezza è coperta dai test, ma il costo reale del nuovo boundary MCP Rust non è ancora osservabile in benchmark.
- Gravita': media.
- Steps to reproduce:
  1. Eseguire i benchmark review-core esistenti.
  2. Controllare i JSON in `docs/benchmarks/review-core/`.
  3. Osservare che non compaiono metriche MCP/shared-state dedicate.
- Risultato attuale: il gap deve restare documentato e diventare la tranche successiva di performance.
- Risultato atteso: aggiungere benchmark su tool MCP review/security/bughunter e queue claim/mark.
- Causa probabile: priorità data al passaggio funzionale di queue e handler prima della telemetria dedicata.
- Scope consentito:
  - `Tests/CoderEngineTests/Validation/*`
  - `scripts/benchmark_review_pipeline_pre_post.sh`
  - `docs/benchmarks/review-core/*`
- Non-scope:
  - modifica dei workflow UI
  - refactor dei panel store
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `ReviewMCPRustBridge`
  - `MCPSharedState+Rust*`
- Test da aggiungere o aggiornare:
  - `mcp_tool_roundtrip_p95_ms`
  - `shared_state_read_p95_ms`
  - `command_queue_claim_p95_ms`
  - `bughunter_query_p95_ms`
- Strategia di fix minimo:
  - aggiungere benchmark dedicati senza cambiare il contratto degli handler
  - riusare il setup `.dylib` forzato già usato per review-core
- Verifica post-fix:
  - generazione nuovi JSON benchmark in `docs/benchmarks/review-core/`
- Commit previsto: `test(review): add mcp rust benchmark coverage`
