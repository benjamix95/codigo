# P1 - Il facade `UnifiedToolRuntime` continuava a possedere il routing canonico dei tool anche con server MCP Rust disponibile

## Bug Fix Record
- Categoria: A
- Bug: anche con `coderide-mcp-server-rust` registrato nel `MCPNativeToolRegistry`, i tool canonici (`read`, `grep`, `plan_*`, `todo_*`, `debug_*`, `skill`, `subagent_*`) restavano instradati dal branching Swift del `UnifiedToolRuntime`.
- Sintomo: il registry MCP esponeva `coderide_*`, ma il runtime non li trattava come alias canonici; di conseguenza il server Rust non diventava owner del path operativo finche' il modello non invocava esplicitamente i nomi `coderide_*`.
- Impatto: migrazione incompleta del boundary runtime, con duplicazione di business logic tra Swift e Rust e cutover finale piu' rischioso.
- Gravita': alta, perche' tocca il facade condiviso di tutti gli strumenti core.
- Steps to reproduce:
  1. Scaldare `MCPNativeToolRegistry` con un tool Rust tipo `coderide_read`.
  2. Eseguire il tool canonico `read`.
  3. Osservare che il runtime Swift continua a usare il path locale invece del route MCP Rust.
- Risultato attuale: i tool canonici non preferivano il route Rust anche con alias nativo disponibile.
- Risultato atteso: se il registry MCP espone un alias `coderide_*` compatibile, il facade Swift deve preferire Rust e ridursi a adapter.
- Causa probabile: il registry MCP conservava solo il routing per il nome function raw, senza una mappa alias verso i nomi canonici del catalogo core.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Tools/Catalog/*`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Dispatch/*`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/MCP/Core/*`
  - `Tests/CoderEngineTests/*`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - rimozione completa dei path Swift locali
  - UI panel
  - command loop app-side
- Moduli confinanti da verificare:
  - `MCPNativeToolRegistry`
  - `UnifiedToolRuntime+RunDispatch`
  - `UnifiedToolRuntimeMCPConsistencyTests`
  - `ToolSchemaCatalogTests`
- Test da aggiungere o aggiornare:
  - unit test registry su alias `coderide_* -> nome canonico`
  - regressione runtime su preferenza MCP per `read`
- Strategia di fix minimo:
  - introdurre alias routing nel registry MCP
  - far preferire al facade Swift il route alias per un set esplicito di tool canonici
  - spezzare i file grandi toccati per restare sotto il limite manutentivo
- Verifica post-fix:
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolSchemaCatalogTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests`
  - build Swift riuscita; esecuzione test bloccata in ambiente da `library load denied by system policy` sul bundle `CoderEngineTests`
- Commit previsto: `refactor(runtime): prefer rust mcp aliases for canonical tools`
