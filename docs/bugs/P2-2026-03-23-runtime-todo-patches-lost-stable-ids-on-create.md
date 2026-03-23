# Bug Fix Record
- Categoria: B
- Bug: i patch runtime todo (`setStatus` / `removeTodo`) potevano non colpire lo stesso elemento creato da `upsertFromAgent`, perché il ramo di creazione ignorava l'`id` passato dal boundary Rust.
- Sintomo: `auto_todo_finalize_runtime` lasciava il todo in `.inProgress` e `auto_todo_discard_runtime` non lo rimuoveva, pur emettendo patch validi.
- Impatto: regressione diretta del boundary `auto-todo` Rust-first, con runtime state coerente ma store host-side non allineato.
- Gravità: media
- Steps to reproduce:
  1. Avviare un runtime auto-todo con `auto_todo_begin_runtime`.
  2. Applicare i patch al `TodoStore`.
  3. Finalizzare o scartare il runtime con `auto_todo_finalize_runtime` / `auto_todo_discard_runtime`.
  4. Osservare che lo stesso todo non cambia stato o non viene rimosso.
- Risultato attuale: il `TodoStore` poteva creare il todo con un UUID diverso da quello richiesto dal boundary runtime, rendendo inefficaci i patch successivi.
- Risultato atteso: quando il runtime fornisce un `todo_id`, il `TodoStore` deve creare il nuovo elemento con quell'identità stabile.
- Causa probabile: `TodoStore.upsertFromAgent` usava l'`id` per i match, ma nel ramo “create new todo” costruiva sempre `TodoItem(...)` con UUID generato localmente.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Mutations.swift`
  - test boundary `RustMainChatAutoTodoBoundaryTests`
- Non-scope:
  - semantica del runtime auto-todo Rust
  - store canonical plan todos
  - pipeline chat live
- Moduli confinanti da verificare:
  - `RustMainChatAutoTodoBoundaryTests`
  - `RustMainChatUIBoundaryTests`
  - `RustMainChatUIBoundaryPlanTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test logico necessario: `RustMainChatAutoTodoBoundaryTests` copriva già il contratto end-to-end e falliva correttamente
- Strategia di fix minimo:
  - usare `id ?? UUID()` nel ramo di creazione di `TodoStore.upsertFromAgent`
  - lasciare invariata la logica di dedup/match esistente
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests`
- Commit previsto: `fix(todo): preserve runtime todo id on create`
