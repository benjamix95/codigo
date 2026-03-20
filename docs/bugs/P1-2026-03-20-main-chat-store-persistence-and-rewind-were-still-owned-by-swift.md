# P1 — Main Chat Store, Persistenza e Rewind Erano Ancora Owned Da Swift

## Categoria
- `A` Critico

## Bug
- Dopo reducer/runtime/provider transport, la `main chat` continuava ad avere come source of truth Swift:
  - `Conversation`
  - `ChatMessage`
  - `PlanBoard`
  - `ConversationCheckpoint`
  - rewind/restore chat state

## Sintomo
- Le mutazioni finali di messaggi, timeline, reasoning, checkpoint e plan board passavano ancora da `ChatStore`.
- Il rewind chat continuava a essere deciso e applicato da store Swift.

## Impatto
- La migrazione `Rust only` della `main chat` restava incompleta sul dominio più delicato: stato persistito e restore.

## Scope Consentito
- `Native/AppCoreProtocol/src/main_chat_store.rs`
- `Native/RustCore/src/main_chat/store/*`
- bridge Swift store chat
- mutazioni live di `ChatStore`

## Non-Scope
- refactor totale del pipeline engine Swift
- restore Git lato filesystem
- nuove feature della chat

## Invarianti Da Preservare
- history locale leggibile senza reset
- `turnMetadata`, `blocks`, `reasoningText`, attachments e checkpoints non si perdono
- rewind chat-only resta possibile anche con restore Git parziale
- `preferredProviderId`, `mode` e `contextMemory*` restano compatibili

## Verifica Post-Fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test` sui golden test store/checkpoint/plan/pipeline
- `SOLOCODE_MAIN_CHAT_CUTOVER=1 ./scripts/validate_rust_cutover_boundary.sh ...`
