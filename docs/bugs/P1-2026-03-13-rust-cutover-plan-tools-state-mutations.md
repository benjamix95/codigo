# P1 - I plan tools MCP restavano Swift-owned su stato, history e diff del piano

## Bug Fix Record
- Categoria: A - Critico
- Bug: gli handler `IDEStatePlan*` nel target `CoderIDEMCPServer` continuavano a leggere/scrivere `plan_state.json` e a calcolare history/diff direttamente in Swift.
- Sintomo: i tool piano avevano ancora una semantica propria lato Swift, separata dal runtime Rust già presente nel server MCP.
- Impatto: ownership duplicata del dominio plan, alto rischio di drift su merge snapshot, snapshot history append-only e diff status changes.
- Gravita': alta
- Steps to reproduce:
  1. Invocare `plan_create`, `plan_step_upsert`, `plan_history_read` o `plan_diff` via handler Swift.
  2. Osservare che la mutazione e la serializzazione del documento piano avvenivano in Swift su `MCPSharedState`.
- Risultato attuale: gli handler plan devono fare solo validazione minima e marshaling; la lettura/scrittura del documento, l’append degli snapshot, il merge e il diff devono vivere nel core Rust.
- Risultato atteso: `plan_state_handle_action` in Rust possiede le operazioni plan; gli handler Swift diventano adapter del bridge.
- Causa probabile: la tranche MCP Rust iniziale aveva portato il catalogo e parte del server, ma non il blocco storico dei plan tools IDE-state.
- Scope consentito:
  - `Native/RustCore/src/plan_state.rs`
  - `Native/RustCore/src/ffi/plan_state.rs`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStatePlan*.swift`
  - build/test di `RustCore`, `Solo Code-Debug`, `CoderEngineTests-Debug`
- Non-scope:
  - migrazione completa di `MCPSharedState` piano
  - rimozione totale degli helper Swift di validazione/normalizzazione input
  - tool `todo_*` e altri IDE-state non-plan
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `CoderIDEMCPServerPlanToolsTests`
  - `MCPSharedPlanStateModels`
- Test da aggiungere o aggiornare:
  - unit test Rust su merge `replace_existing=false`
  - unit test Rust su mutazione che crea snapshot implicito
  - unit test Rust su `diff` con status changes
  - build smoke dei target Swift che importano `CoderIDEMCPServer`
- Strategia di fix minimo:
  - aggiungere un handler FFI plan coarse-grained in `RustCore`
  - riusare in Swift solo validazione argomenti e conversione payload verso stringhe/JSON
  - delegare create/read/history/update/upsert/batch/reorder/dependency/walkthrough/diff/request_user_input al core Rust
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml plan_state -- --nocapture`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
- Commit previsto: `refactor(rust-cutover): route plan tools through rust state core`

## Note
- In Swift restano helper di parsing/validazione per mantenere invariati gli error message già coperti dai test; la mutazione dello stato piano non e' più owned da Swift.
