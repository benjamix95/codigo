# P1 - I tool `todo_*` restavano Swift-owned su read/write e canonicalizzazione

## Bug Fix Record
- Categoria: A - Critico
- Bug: `todo_write` e `todo_read` nel blocco `IDEStateTools` continuavano a possedere la semantica di validazione locale, write/read del file `todos.json` e formattazione dell’output nel server Swift.
- Sintomo: il runtime MCP poteva ancora gestire i todo fuori dal core Rust, con rischio di drift rispetto alla canonicalizzazione dell’app e del server Rust.
- Impatto: ownership non unificata del dominio todo, rischio di regressioni su dedupe per titolo/ID e stato mostrato al modello.
- Gravita': alta
- Steps to reproduce:
  1. Invocare `todo_write` con payload legacy senza id oppure con checklist string.
  2. Osservare che il server Swift validava e rispondeva senza delegare al core Rust.
  3. Invocare `todo_read` e osservare che la formattazione del riepilogo avveniva nel server Swift.
- Risultato attuale: i tool `todo_*` devono delegare la semantica di persistence/canonicalizzazione al core Rust; Swift deve restare parser/adapter degli input misti.
- Risultato atteso: il core Rust possiede read/write/canonicalizzazione dei todo e restituisce l’output già canonico.
- Causa probabile: i todo facevano parte del vecchio blocco IDE-state lasciato intenzionalmente nel server Swift come pass-through iniziale.
- Scope consentito:
  - `Native/RustCore/src/todo_state.rs`
  - `Native/RustCore/src/ffi/todo_state.rs`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStateTools.swift`
  - build/test Rust e build Swift dei target MCP/app
- Non-scope:
  - migrazione completa di tutto `MCPSharedState`
  - tool `debug_*`, `policy_ack`, `show_*`
  - refactor UI di `TodoStore`
- Moduli confinanti da verificare:
  - `IDEStateTodoArgumentParser`
  - `MCPSharedState.writeTodos/readTodos`
  - target `CoderIDEMCPServer` e `CoderIDEMCPServerExecutable`
- Test da aggiungere o aggiornare:
  - unit test Rust sulla canonicalizzazione:
    - explicit id distinti non vengono fusi
    - payload legacy senza id si fondono per titolo
    - explicit id + legacy title non si fondono
  - build smoke dei target Swift che importano `IDEStateTools`
- Strategia di fix minimo:
  - aggiungere core Rust `todo_state` con read/write e formattazione testo
  - lasciare in Swift il parsing checklist/JSON per mantenere invariato il contratto input
  - instradare `todo_write`/`todo_read` al bridge Rust
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml todo_state -- --nocapture`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- Commit previsto: `refactor(rust-cutover): route todo tools through rust state core`

## Note
- In Swift resta il parser `IDEStateTodoArgumentParser` perché serve a normalizzare checklist e payload ibridi prima del bridge, ma la semantica dello stato todo non è più owned dal server Swift.
