# Audit Rust MCP Tools - 2026-03-29

## Scope
- Workspace analizzato: `Native/CoderideMCPServerRust`, `Native/MCPLifecycleBackendRust`, `Native/RustCore`, `Native/AppCoreProtocol`.
- Perimetro: tutti i tool MCP Rust pubblicati da `Native/CoderideMCPServerRust/src/tool_names.txt` e il lifecycle backend MCP che li avvia/chiama.
- Metodo: lettura del catalogo/dispatch, review mirata dei moduli ad alto rischio, `cargo test` sui crate Rust MCP, `cargo clippy --all-targets -- -D warnings` come verifica statica.

## Inventario Tool

### Audit (31)
`coderide_audit_bug_api_contracts`, `coderide_audit_bug_concurrency`, `coderide_audit_bug_dependency_drift`, `coderide_audit_bug_diff_risks`, `coderide_audit_bug_diff_semantics`, `coderide_audit_bug_error_handling`, `coderide_audit_bug_hotspots`, `coderide_audit_bug_nil_crash_paths`, `coderide_audit_bug_state_machine`, `coderide_audit_bug_test_gaps`, `coderide_audit_bug_test_impact`, `coderide_audit_correlate_findings`, `coderide_audit_explain_finding`, `coderide_audit_run_profile`, `coderide_audit_security_authz`, `coderide_audit_security_crypto`, `coderide_audit_security_dataflow`, `coderide_audit_security_dependencies`, `coderide_audit_security_deserialization`, `coderide_audit_security_patterns`, `coderide_audit_security_secrets`, `coderide_audit_security_supply_chain`, `coderide_audit_security_surface`, `coderide_audit_verify_bundle`, `coderide_audit_perf_bottlenecks`, `coderide_audit_perf_memory`, `coderide_audit_perf_ui_responsiveness`, `coderide_audit_perf_startup`, `coderide_audit_perf_hot_paths`, `coderide_audit_perf_correlate`, `coderide_audit_perf_trending`

### BugHunter (12)
`coderide_bughunter_autofix_apply`, `coderide_bughunter_autofix_commit`, `coderide_bughunter_autofix_preview`, `coderide_bughunter_cancel_run`, `coderide_bughunter_commit_window`, `coderide_bughunter_explain_cluster`, `coderide_bughunter_findings`, `coderide_bughunter_install_hook`, `coderide_bughunter_run_history`, `coderide_bughunter_start`, `coderide_bughunter_status`, `coderide_bughunter_uninstall_hook`

### Codebase (7)
`coderide_codebase_search`, `coderide_file_outline`, `coderide_find_files`, `coderide_find_references`, `coderide_find_symbol`, `coderide_read_lints`, `coderide_semantic_search`

### Debug (15)
`coderide_debug_clean`, `coderide_debug_context`, `coderide_debug_hypothesize`, `coderide_debug_instrument`, `coderide_debug_log`, `coderide_debug_mark`, `coderide_debug_query`, `coderide_debug_request_user`, `coderide_debug_resolve`, `coderide_debug_session`, `coderide_debug_set_phase`, `coderide_debug_snapshot`, `coderide_debug_test_check`, `coderide_debug_timeline`, `coderide_debug_trace_analyze`

### Diagnostics (6)
`coderide_benchmark_indexing`, `coderide_benchmark_review_pipeline`, `coderide_benchmark_semantic_search`, `coderide_diagnostics`, `coderide_export_debug_bundle`, `coderide_run_tests`

### Edit (4)
`coderide_create_file`, `coderide_regex_replace`, `coderide_str_replace`, `coderide_write`

### File (3)
`coderide_list_dir`, `coderide_read`, `coderide_read_range`

### Git (1)
`coderide_git_diff`

### Plan (13)
`coderide_activate_debug_mode`, `coderide_activate_plan_mode`, `coderide_plan_create`, `coderide_plan_diff`, `coderide_plan_history_read`, `coderide_plan_read`, `coderide_plan_request_user_input`, `coderide_plan_set_walkthrough`, `coderide_plan_step_batch_update`, `coderide_plan_step_dependency_set`, `coderide_plan_step_reorder`, `coderide_plan_step_update`, `coderide_plan_step_upsert`

### Policy (2)
`coderide_mermaid_render`, `coderide_policy_ack`

### Review (21)
`coderide_review_apply_fix`, `coderide_review_apply_patch`, `coderide_review_close_finding`, `coderide_review_comment`, `coderide_review_configure`, `coderide_review_diff_summary`, `coderide_review_dismiss`, `coderide_review_findings`, `coderide_review_get_outcome`, `coderide_review_list_sessions`, `coderide_review_merge_pr`, `coderide_review_open_pr`, `coderide_review_prepare_patch`, `coderide_review_preview_patch`, `coderide_review_resolve_conflicts`, `coderide_review_revalidate_finding`, `coderide_review_rollback_patch`, `coderide_review_start`, `coderide_review_status`, `coderide_review_verify_finding`, `coderide_review_verify_patch`

### Search (2)
`coderide_glob`, `coderide_grep`

### Security (11)
`coderide_security_apply_patch`, `coderide_security_close_finding`, `coderide_security_findings`, `coderide_security_prepare_patch`, `coderide_security_preview_patch`, `coderide_security_revalidate_finding`, `coderide_security_rollback_patch`, `coderide_security_start`, `coderide_security_status`, `coderide_security_verify_finding`, `coderide_security_verify_patch`

### Skill (1)
`coderide_skill`

### Subagent (8)
`coderide_subagent_bugHunter`, `coderide_subagent_coder`, `coderide_subagent_debugger`, `coderide_subagent_docWriter`, `coderide_subagent_explorer`, `coderide_subagent_reviewer`, `coderide_subagent_securityAuditor`, `coderide_subagent_testWriter`

### Todo (2)
`coderide_todo_read`, `coderide_todo_write`

### Ui (2)
`coderide_show_swarm_panel`, `coderide_show_task_panel`

### Web (2)
`coderide_web_fetch`, `coderide_web_search`

## Findings

### [P0] `debug_*` non compila nello stato locale corrente
- Categoria: A — Critico
- Bug: il gruppo `coderide_debug_mark`, `coderide_debug_clean` e `coderide_debug_instrument` contiene blocchi incompleti e `format!` senza stringa letterale.
- Sintomo: ricompilazioni mirate del server Rust falliscono con errori di compilazione in `debug_tools.rs`.
- Impatto: il binario MCP Rust può diventare non buildabile; i tool debug risultano indisponibili e bloccano anche test mirati che ricompilano il target.
- Scope consentito: [`Native/CoderideMCPServerRust/src/debug_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L928), [`Native/CoderideMCPServerRust/src/debug_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L976), [`Native/CoderideMCPServerRust/src/debug_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L1066)
- Non-scope: review/security/bughunter core, lifecycle backend.
- Expected result: i tool debug devono ricompilare e produrre marker/strumentazione validi.
- Rischi laterali: essendo un file da 1500+ righe, il fix andrebbe confinato e coperto da test unitari sui generatori di marker.
- Verifica osservata: `cargo test -p coderide_mcp_server_rust --test catalog_contract tools_list_matches_frozen_catalog_size_and_annotations -- --nocapture` ha fallito in compilazione sul target binario.
- Strategia di fix minimo: ripristinare i rami `match` incompleti, aggiungere test dedicati per `debug_mark`, `debug_clean`, `debug_instrument`.

### [P1] `coderide_web_fetch` accetta schemi arbitrari e `coderide_web_search` non fa URL-encoding corretto
- Categoria: A — Critico
- Bug: `web_fetch` inoltra a `curl` qualsiasi schema presente nella stringa (`file://`, `ftp://`, `dict://`, ecc.); `web_search` costruisce la query con un semplice `replace(' ', '+')`.
- Sintomo: un caller può leggere file locali o endpoint non HTTP; query con `&`, `+`, `?`, `%`, Unicode o newline cambiano semantica o rompono la ricerca.
- Impatto: superficie SSRF / local file disclosure per `coderide_web_fetch`; risultati incoerenti o manipolabili per `coderide_web_search`.
- Scope consentito: [`Native/CoderideMCPServerRust/src/web_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/web_tools.rs#L22), [`Native/CoderideMCPServerRust/src/web_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/web_tools.rs#L54)
- Non-scope: tool search/file/edit.
- Expected result: i tool web devono consentire solo `http`/`https`, validare l’URL e percent-encodare la query.
- Rischi laterali: regressioni su caller che oggi passano schemi non supportati ma non desiderabili.
- Test da aggiungere o aggiornare: unit test su allowlist schemi e URL encoding di query contenenti caratteri speciali.
- Strategia di fix minimo: parse con `url::Url`, allowlist schemi, usare encoder query-safe invece di replace manuale.

### [P1] `coderide_todo_write` ha due bug di consistenza: clear finto e replace bulk senza lock
- Categoria: A — Critico
- Bug: il ramo `todos=""` ritorna “clear request acknowledged” ma non cancella nulla; i rami bulk (`array`, `object`, `JSON string`) scrivono direttamente senza `with_file_lock`, a differenza del path append.
- Sintomo: richieste di clear non hanno effetto; scritture concorrenti Swift/Rust possono perdere update o corrompere lo stato logico.
- Impatto: stato TODO incoerente, race cross-process su `todos.json`, UX fuorviante perché l’ack non riflette il risultato reale.
- Scope consentito: [`Native/CoderideMCPServerRust/src/shared_state.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/shared_state.rs#L59)
- Non-scope: plan state, review queues.
- Expected result: tutte le mutazioni TODO devono passare sotto lock esclusivo e il clear deve davvero scrivere una lista vuota.
- Rischi laterali: basso, confinato al file condiviso `todos.json`.
- Test da aggiungere o aggiornare: regression test per clear, test concorrente append-vs-replace, test bulk object/array.
- Strategia di fix minimo: spostare tutti i rami di scrittura dentro `with_file_lock`; trasformare `trimmed.is_empty()` in `write_json_array(vec![])`.

### [P1] Il lifecycle backend MCP scarta messaggi JSON-RPC inattesi e azzera `stderr`
- Categoria: A — Critico
- Bug: `read_response` scarta silenziosamente notifiche/richieste con `id` diverso da quello atteso; inoltre il child process viene spawnato con `stderr` su `Stdio::null()`.
- Sintomo: server MCP che inviano richieste server-initiated, notifiche importanti o risposte fuori ordine possono mandare il client in stato incoerente; i crash lato server diventano poco osservabili.
- Impatto: perdita di messaggi protocol-level, deadlock diagnostico, hardening insufficiente nella gestione di server MCP non banali.
- Scope consentito: [`Native/MCPLifecycleBackendRust/src/mcp_process.rs`](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/mcp_process.rs#L23), [`Native/MCPLifecycleBackendRust/src/mcp_process.rs`](/Users/benjaminstoica/SoloCode/Native/MCPLifecycleBackendRust/src/mcp_process.rs#L248)
- Non-scope: catalogo tool del server Rust.
- Expected result: richieste/notifications inattese vanno instradate o bufferizzate; `stderr` va raccolto almeno per logging/debug.
- Rischi laterali: moderati, perché tocca il bridge con tutti i server MCP.
- Test da aggiungere o aggiornare: smoke test con fake server che invia notification, server request con `id`, e risposta fuori ordine.
- Strategia di fix minimo: introdurre una coda per messaggi non corrispondenti, rispondere esplicitamente a richieste non supportate e conservare `stderr`.

### [P1] `coderide_debug_test_check` e `coderide_run_tests` sono fragili su Xcode/iOS
- Categoria: B — Importante ma non bloccante
- Bug: `debug_test_check` usa `cmd.output()` senza timeout e forza `platform=macOS`; `run_tests` sceglie il primo `.xcodeproj` e usa sempre `xcodebuild ... -destination platform=macOS`.
- Sintomo: test Xcode lunghi o app iOS possono bloccare il tool o fallire sul destination sbagliato; nei workspace con più progetti si può testare il progetto errato.
- Impatto: affidabilità bassa per tool di verifica e support workflow; divergenza rispetto alla policy operativa del repo che richiede `xcodebuildmcp` per i test iOS.
- Scope consentito: [`Native/CoderideMCPServerRust/src/debug_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs#L757), [`Native/CoderideMCPServerRust/src/support_workflow_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/support_workflow_tools.rs#L29)
- Non-scope: benchmark semantici.
- Expected result: routing corretto tra macOS/iOS, timeout espliciti, scelta deterministica del progetto/scheme, uso del bridge adatto per Xcode.
- Rischi laterali: cambio comportamento per workspace che si affidavano al fallback implicito.
- Test da aggiungere o aggiornare: unit test sul resolver di destination/scheme e smoke test con workspace multiprogetto.
- Strategia di fix minimo: introdurre un adapter Xcode comune con timeout, detection piattaforma e supporto `xcodebuildmcp`.

### [P2] `coderide_semantic_search` vanifica parte della cache e ricostruisce snapshot pesanti a ogni query
- Categoria: D — Miglioramento travestito da bug, ma con impatto reale sulle performance
- Bug: `load_semantic_chunks` clona l’intero `Vec<PersistedSemanticChunk>` dall’`Arc`; `semantic_search_via_persisted_index` ricostruisce ogni volta snapshot BM25, mappe e stringhe contestualizzate.
- Sintomo: allocazioni elevate, latenza crescente e pressione memoria con indici grandi; la cache evita il parse del JSONL ma non evita il costo dominante successivo.
- Impatto: throughput scarso su ricerche semantiche ripetute, soprattutto su codebase grandi.
- Scope consentito: [`Native/CoderideMCPServerRust/src/diagnostics_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/diagnostics_tools.rs#L385), [`Native/CoderideMCPServerRust/src/diagnostics_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/diagnostics_tools.rs#L533)
- Non-scope: lexical fallback `run_rg`.
- Expected result: riuso strutture indicizzate persistenti o memoizzate per cache key e filtri frequenti.
- Rischi laterali: invalidazione cache più complessa.
- Strategia di fix minimo: restituire `Arc<Vec<_>>` o slice condivise, separare snapshot precomputata dalla presentazione finale, aggiungere benchmark regressione.

### [P2] Il contract test del catalogo è rimasto a 142 tool mentre il catalogo Rust ne dichiara 143
- Categoria: B — Importante ma non bloccante
- Bug: il contract test hardcodato nel test integration non segue `CATALOG_TOOL_COUNT`.
- Sintomo: `cargo test -p coderide_mcp_server_rust` fallisce su `tools_list_matches_frozen_catalog_size_and_annotations`.
- Impatto: falsa regressione in CI/local, riduzione della fiducia nella suite.
- Scope consentito: [`Native/CoderideMCPServerRust/src/catalog.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/catalog.rs#L4), [`Native/CoderideMCPServerRust/tests/catalog_contract.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/tests/catalog_contract.rs#L8)
- Non-scope: implementazione dei singoli tool.
- Expected result: il test deve derivare il numero atteso dal catalogo o da una costante unica.
- Rischi laterali: nessuno.
- Verifica osservata: `cargo test -p coderide_mcp_server_rust` ha fallito su `assert_eq!(tools.len(), 142)` mentre il catalogo espone 143 tool.
- Strategia di fix minimo: importare `CATALOG_TOOL_COUNT` nel test oppure evitare numeri magici.

### [P3] Debito di manutenibilità: moduli troppo grandi rispetto alla policy del repo
- Categoria: D — Miglioramento travestito da bug
- Bug: diversi moduli MCP Rust superano ampiamente il limite operativo richiesto nel repo.
- Sintomo: review più difficile, rischio di regressioni locali più alto, merge conflict più frequenti.
- Impatto: hardening lento e costoso nelle aree più fragili.
- Scope consentito: [`Native/CoderideMCPServerRust/src/debug_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs), [`Native/CoderideMCPServerRust/src/diagnostics_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/diagnostics_tools.rs), [`Native/CoderideMCPServerRust/src/review_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/review_tools.rs), [`Native/CoderideMCPServerRust/src/search_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/search_tools.rs), [`Native/CoderideMCPServerRust/src/plan_state.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/plan_state.rs)
- Expected result: split per adapter/servizio/utility, file sotto ~300 righe nei punti più fragili.
- Strategia di fix minimo: estrarre generatori marker, runner xcode, parser semantic search, persistence state e formatter output in moduli dedicati.

## Copertura e note per famiglia
- `audit_*`: buona centralizzazione via `run_audit`, ma dipendenza forte da RustCore e poca copertura end-to-end del bridge MCP.
- `review_*`, `security_*`, `bughunter_*`: superficie ampia ma abbastanza confinata; rischio principale nella persistenza queue/snapshot e nel coupling con shared state.
- `file_*`, `edit_*`, `search_*`, `codebase_*`: sandbox path presente e utile; mancano test mirati su edge case UTF-8/non-text e su performance dei fallback nativi.
- `debug_*`: famiglia più fragile oggi, sia per compile break locale sia per execution Xcode diretta.
- `diagnostics_*`, `benchmark_*`, `web_*`: tool più esposti a comandi esterni/network, quindi sono l’area prioritaria per timeout, validation e hardening.
- `plan_*`, `todo_*`, `skill`, `subagent_*`, `ui/policy`: diverse route sono sostanzialmente ack/stub; servono test che garantiscano che il comportamento dichiarato coincida con l’effetto reale atteso dal caller.

## Verifiche eseguite
- `cargo test -p coderide_mcp_server_rust`
  Risultato: suite unit test ok, contract test `tools_list_matches_frozen_catalog_size_and_annotations` fallito per drift 142/143.
- `cargo test -p mcp_lifecycle_backend_rust`
  Risultato: ok.
- `cargo test -p solocode_rust_core ffi::review_mcp`
  Risultato: ok, ma senza casi runtime specifici sul bridge.
- `cargo clippy -p coderide_mcp_server_rust --all-targets -- -D warnings`
  Risultato: bloccato da un warning/errore in `AppCoreProtocol` (`too_many_arguments`) prima di completare la review del target.
- `cargo clippy -p mcp_lifecycle_backend_rust --all-targets -- -D warnings`
  Risultato: stesso blocco su `AppCoreProtocol`.

## Priorità consigliata
1. Ripristinare la compilazione dei tool `debug_*`.
2. Hardening immediato di `web_fetch`/`web_search`.
3. Correggere `todo_write` per clear reale e lock uniforme.
4. Mettere in sicurezza il lifecycle backend JSON-RPC.
5. Sistemare `debug_test_check` / `run_tests` per Xcode/iOS.
6. Allineare il contract test del catalogo.
7. Ottimizzare `semantic_search` con cache strutturale reale.
