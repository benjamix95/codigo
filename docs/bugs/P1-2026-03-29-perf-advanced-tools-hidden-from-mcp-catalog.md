# P1 — `audit_perf_correlate` e `audit_perf_trending` esistono nel core Rust ma non nel catalogo MCP

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il core Rust supportava `audit_perf_correlate` e `audit_perf_trending`, ma i due tool non erano pubblicati in `tool_names.txt` / `tool_descriptions.json` / registry canonico. Inoltre `tools/list` serviva descrizioni audit generiche invece di quelle specifiche canoniche.
- Sintomo: via `tools/list` il client non vedeva i due tool avanzati; i perf tool pubblicati mostravano descrizioni generiche non coerenti con il catalogo canonico.
- Impatto: i tool erano parzialmente orfani: implementati ma non discoverable dal lato MCP, quindi non richiamabili in chat né documentabili correttamente.
- Gravità: P1
- Steps to reproduce:
  1. Cercare `audit_perf_correlate` e `audit_perf_trending` in `Native/RustCore/src/review_audit/dispatch.rs`.
  2. Confrontare con `Config/tooling/canonical_tool_registry.json` e `Native/CoderideMCPServerRust/src/tool_names.txt`.
  3. Eseguire `tools/list` sul server MCP Rust.
- Risultato attuale: i due tool non compaiono nel catalogo MCP; `coderide_audit_perf_bottlenecks` e simili espongono descrizioni generiche da fallback audit.
- Risultato atteso: i due tool devono essere pubblicati nel catalogo MCP e `tools/list` deve servire le descrizioni canoniche specifiche.
- Causa probabile: drift tra implementazione RustCore e source registry canonico; `tool_descriptions.rs` privilegiava il fallback audit invece della mappa JSON canonica.
- Scope consentito:
  - `Config/tooling/canonical_tool_registry.json`
  - `Native/CoderideMCPServerRust/src/tool_descriptions.rs`
  - artefatti generati catalogo/descriptions
  - costanti e schema Swift lato engine
  - test contratto catalogo
- Non-scope: redesign dei profili performance, modifica dei benchmark script interni.
- Moduli confinanti da verificare: `tools/list`, alias runtime, `ToolSchemaCatalog`, `ReviewAuditToolName`, runtime dispatch audit.
- Test da aggiungere o aggiornare:
  - test Rust `catalog_contract` su presenza dei due tool e descrizione specifica
  - test Swift su `allToolNames` / alias registry per i due tool
- Strategia di fix minimo: pubblicare i due tool nel registry canonico, rigenerare artefatti e invertire la priorità di lookup descrizioni (`tool_descriptions.json` prima del fallback audit generico).
- Verifica post-fix:
  1. `tools/list` mostra `coderide_audit_perf_correlate` e `coderide_audit_perf_trending`
  2. descrizioni specifiche corrette
  3. `tools/call` sui due tool risponde correttamente
- Commit previsto: `fix(mcp): publish advanced perf audit tools`
