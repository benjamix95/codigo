# P1 — Codex App Server non rendeva esplicita la discoverability MCP locale e perdeva il trace di `Tool search`

## Bug Fix Record
- Categoria: B
- Bug: il path Codex App Server aveva MCP `coderide` configurato, ma non forzava abbastanza l'uso dei tool `coderide_*` e non trasformava le righe interne `select:...` in un evento strutturato `tool_search`.
- Sintomo: Codex tendeva a usare o nominare tool generici; quando faceva selection interna dei tool, la chat poteva mostrare righe grezze o non mostrare affatto un card `Tool search`.
- Impatto: discoverability MCP meno affidabile rispetto a Claude, minore aderenza al catalogo locale `coderide_*`, trace dei tool meno leggibile.
- Gravita': P1
- Steps to reproduce:
  1. Avviare una sessione Codex sul transport App Server con MCP `coderide` provisionato.
  2. Fare un task di code discovery che richieda search/read multipli.
  3. Osservare che Codex non viene spinto in modo forte verso `coderide_*` e che eventuali righe `select:mcp__coderide__...` non emergono come evento `Tool search`.
- Risultato attuale: MCP configurato ma discoverability e trace non sufficientemente espliciti sul path Codex.
- Risultato atteso: prompt provider-specifico MCP-first, scelta preferenziale dei tool `coderide_*`, emissione strutturata di `tool_search` per le selection interne, nessuna riga `select:` grezza nella prose utente.
- Causa probabile:
  - assenza di un prompt Codex provider-specifico paragonabile a quello Claude;
  - bridge Rust che non parseava le selection interne `select:...`;
  - filtro UI che non sopprimeva le righe `select:` nella prose.
- Scope consentito:
  - `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`
  - nuovi helper `codex_app_server_prompt.rs`, `codex_app_server_tool_search.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/CoderideDisplayLineFilter.swift`
  - test correlati Rust/Swift
- Non-scope:
  - refactor totale del transport Codex App Server
  - redesign UI del Task Activity panel
  - modifica del catalogo MCP Rust `coderide`
- Moduli confinanti da verificare:
  - merge prompt `baseInstructions`
  - streaming `item/agentMessage/delta` e `item/completed`
  - filtro testo chat lato Swift
- Test da aggiungere o aggiornare:
  - unit test Rust per merge prompt Codex provider-specifico
  - unit test Rust per parser incrementale `select:...`
  - test Swift per filtro display delle righe `select:...`
- Strategia di fix minimo:
  - aggiungere un prompt Codex provider-specifico MCP-first;
  - introdurre un parser incrementale piccolo e isolato per `tool_search`;
  - filtrare le righe `select:` dalla prose visibile.
- Verifica post-fix:
  - `cargo test` mirato sui moduli `codex_app_server_*`
  - test Swift/Xcode mirato su `ChatStreamFailureHandlingTests`
- Commit previsto: `fix(codex): enforce coderide MCP discovery and surface tool search`
