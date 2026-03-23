# 2026-03-23 — Main chat UI boundary state centralization

## Cosa cambia

- la costruzione di `MainChatUIStateBridge` per la main chat non viene più ricomposta a mano nei binding `stream`, `plan` e `auto-todo`;
- `ChatPanelView` espone ora helper unificati per:
  - risolvere lo `runtimeSnapshot` attivo della main chat;
  - costruire il `MainChatUIStateBridge`;
  - applicare intent sul boundary Rust;
  - proiettare snapshot UI dal boundary Rust;
- i path `plan`, `stream/finalizers` e `auto-todo` usano lo stesso helper, riducendo divergenze locali su `selectedConversationId`, `followLive`, `planPanelVisible`, `collapsedArtifactIdsByTurn` e `autoTodoRuntimeStateByMessage`;
- `TodoStore.upsertFromAgent` ora rispetta l'`id` fornito dal runtime/boundary agent quando crea un nuovo todo, così i patch `setStatus/remove` colpiscono lo stesso elemento.

## File toccati

- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_AutoTodoRuntime.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_Finalizers.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartO_PlanPromptBuilders.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Mutations.swift`

## Ownership

- la shell-state della main chat resta host-side, ma il suo boundary è ora costruito in un solo punto per i principali path Rust-backed;
- questo riduce la seconda ownership Swift “nascosta” nel modo in cui i binding preparano lo stato per il core Rust;
- resta ancora un call-site duplicato nel send runtime con modifiche locali non verificate, quindi la tranche 3 è sostanzialmente ma non totalmente esaurita.

## Verifica

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryPlanTests -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 sostanzialmente completata, con un call-site sporco ancora non drenato
- avanzamento complessivo: `55%`
