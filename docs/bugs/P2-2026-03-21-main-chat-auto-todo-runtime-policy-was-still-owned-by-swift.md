# P2 - La policy runtime degli AutoTodo della main chat era ancora Swift-owned

## Bug Fix Record
- Categoria: B
- Bug: la creazione, l’aggiornamento e la finalizzazione degli auto-todo runtime della chat vivevano ancora in Swift, con stato effimero locale sparso tra trace lifecycle, helper string-based e mutazioni dirette del `TodoStore`.
- Sintomo: la shell Swift decideva titolo, linked files, note runtime, conteggio operazioni e status finale degli auto-todo, mantenendo anche bookkeeping locale per assistant message.
- Impatto: ownership di dominio non ancora spostata in Rust, maggiore rischio di drift tra trace runtime e store todo, e impossibilità di usare `main_chat_ui` come boundary unico anche per il ramo AutoTodo.
- Gravità: P2
- Steps to reproduce:
  1. Aprire [ChatPanelView+PartF_AutoTodoRuntime.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_AutoTodoRuntime.swift).
  2. Verificare che `startAutoTodoIfNeeded` e `refreshAutoTodoIfNeeded` costruiscano direttamente titolo, note, active form e linked files e mutino `TodoStore`.
  3. Aprire [ChatPanelView+PartF_DebugTodoLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_DebugTodoLifecycle.swift) e verificare la finalizzazione diretta `done/blocked`.
- Risultato attuale: la policy AutoTodo era distribuita tra helper Swift e lifecycle `TaskTrace`.
- Risultato atteso: il dominio Rust deve produrre patch todo già risolte; Swift applica solo le patch al `TodoStore`.
- Causa probabile: tranche precedenti concentrate su stream/planning hanno lasciato il ramo AutoTodo come isola Swift locale.
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_ui.rs`
  - `Native/RustCore/src/main_chat/auto_todo*.rs`
  - `Native/RustCore/src/main_chat/ui_intents.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/**`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/**`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/UI/ChatPanelView+TodoCardSelection.swift`
- Non-scope:
  - canonical plan todos
  - provider/accounts
  - review-todo post-turn
  - persistenza generale di `TodoStore`
- Moduli confinanti da verificare:
  - `ChatTodoVisibilityTests`
  - `ToolTraceVisibilityTests`
  - `ConversationFlowCoordinatorTests`
  - `RustMainChatUIBoundaryTests`
- Test da aggiungere o aggiornare:
  - `RustMainChatAutoTodoBoundaryTests`
  - `ui_tests.rs`
  - `main_chat_ui.rs` FFI tests
- Strategia di fix minimo:
  - introdurre `auto_todo.rs` in Rust e nuove `todo_patches` nel boundary `main_chat_ui`
  - mantenere `TodoStore` Swift come adapter, non owner della policy
  - rimuovere il file legacy `ChatPanelSupport+AutoTodo.swift`
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
  - `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests`
- Commit previsto: `feat(chat): move auto todo runtime policy into rust`

## Esito
- introdotto il reducer Rust `auto_todo` dentro il dominio `main_chat`
- `main_chat_ui` ora restituisce `todo_patches` applicabili direttamente al `TodoStore`
- il bookkeeping `autoTodoIdByMessage` / `autoTodoCompletedOperationsByMessage` è stato sostituito da stato bridge Rust-owned
- rimosso il file legacy [ChatPanelSupport+AutoTodo.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+AutoTodo.swift)
