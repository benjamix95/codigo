# P1 — tool `audit_perf_*` fuori sync tra catalogo, runtime e chat

## Bug Fix Record
- Categoria: A - Critico
- Bug: i nuovi tool performance audit esistevano solo parzialmente: presenti nel registry Swift generato ma assenti dal source registry canonico e dagli artefatti Rust `tools/list`; inoltre mancavano pezzi di wiring runtime/chat.
- Sintomo: i tool `audit_perf_*` potevano risultare non pubblicati nel catalogo MCP, non avere alias coerenti, non apparire come eventi ricchi in chat e, in alcune modalità, essere trattati come mutanti invece che read-only.
- Impatto: discovery incompleta via `tools/list`, rischio di drift alla prossima rigenerazione, dispatch runtime incompleto e visibilità degradate quando i tool vengono richiamati in chat.
- Gravità: P1
- Steps to reproduce:
  1. Confrontare `Config/tooling/canonical_tool_registry.json` con `Engine/CoderEngine/Sources/Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift`.
  2. Verificare che `Native/CoderideMCPServerRust/src/tool_names.txt` e `tool_descriptions.json` non elenchino `audit_perf_*`.
  3. Controllare `UnifiedToolRuntime+RunCoreDispatch.swift` e `IDEStateSyntheticEventFactory.swift`.
- Risultato attuale: drift fra source of truth e artefatti derivati, perf tool assenti dal catalogo Rust, fallback runtime incompleto, famiglia `audit` non inclusa nel synthetic mapping della chat.
- Risultato atteso: i tool `audit_perf_*` devono essere dichiarati nel registry canonico, rigenerati negli artefatti Rust/Swift, dispatchati dal runtime, riconosciuti come read-only e mostrati correttamente in chat con alias coerenti.
- Causa probabile: introduzione dei perf tool fatta solo su artefatti derivati e test locali, senza completare la catena `source registry -> generated files -> Rust tools/list -> runtime/chat wiring`.
- Scope consentito:
  - `Config/tooling/canonical_tool_registry.json`
  - artefatti generati `tool_names.txt`, `tool_descriptions.json`, `CoderIDECanonicalToolRegistry+Generated.swift`, `CoderIDETools+RustSyncedDescriptions.swift`
  - runtime `UnifiedToolRuntime+RunCoreDispatch.swift`
  - chat/event mapping `IDEStateSyntheticEventFactory*.swift`
  - policy read-only `ToolEnabledLLMProvider+ToolStartPolicy.swift`
  - test mirati `PerformanceAuditToolIntegrationTests.swift`, `WorkspaceCatalogToolTests.swift`, `catalog_contract.rs`
- Non-scope: redesign dei profili audit, refactor esteso del catalogo, modifica delle altre famiglie tool non coinvolte.
- Moduli confinanti da verificare: registry alias, `tools/list` Rust, `ProviderToolEventMapper`, policy read-only e visibilità in trace/chat.
- Test da aggiungere o aggiornare:
  - test alias e runtime per `audit_perf_*`
  - test chat synthetic event per `audit_perf_*`
  - contratto Rust catalog `tool_names.txt` / `tool_descriptions.json`
- Strategia di fix minimo: aggiungere i cinque perf tool al source registry con alias, rigenerare gli artefatti, completare il dispatch runtime e il mapping `audit` in chat, marcare i perf tool come read-only nel percorso di enforcement.
- Verifica post-fix:
  1. `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' ...` -> verde
  2. `cargo test` in `Native/CoderideMCPServerRust` -> verde
  3. `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' ...` -> verde sul set mirato
- Commit previsto: `fix(audit): publish perf tools in catalog and restore chat/runtime wiring`
