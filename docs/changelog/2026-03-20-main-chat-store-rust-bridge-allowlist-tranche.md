# 2026-03-20 — Main Chat StoreRust bridge allowlist tranche

## Modifiche
- aggiornato [rust-cutover-swift-allowlist.txt](/Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt) per classificare `App/SoloCodeApp/Sources/Chat/Support/StoreRust/**` come `binding_adapter`
- aggiornata la regressione [app_core_boundary_main_chat.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/app_core_boundary_main_chat.rs) per verificare che:
  - `StoreRust/**` venga trattato come `allowed`
  - il prefisso largo `App/SoloCodeApp/Sources/Chat` continui a raccogliere backlog nested reale
- aggiunto il bug record [P2-2026-03-20-main-chat-store-rust-bridge-files-were-still-counted-as-legacy.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-20-main-chat-store-rust-bridge-files-were-still-counted-as-legacy.md)
- aggiornata [RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md](/Users/benjaminstoica/SoloCode/docs/migration/RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md) con il nuovo conteggio osservato dopo la riclassificazione

## Risultato
- i tre file bridge-only del blocco `StoreRust` non vengono piu' conteggiati come legacy Swift non-UI:
  - `ChatStore+RustBridge.swift`
  - `MainChatStoreBridgeModels.swift`
  - `RustMainChatStoreAdapter.swift`
- il backlog strutturale canonico `main chat` scende da `198` a `195`
- avanzamento strutturale canonico: `3 / 198 = 1.5%`

## Verifica
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "Config/validation/rust-cutover-swift-allowlist.txt,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs" --format text`
- `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "Config/validation/rust-cutover-swift-allowlist.txt,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs,docs/bugs/P2-2026-03-20-main-chat-store-rust-bridge-files-were-still-counted-as-legacy.md,docs/changelog/2026-03-20-main-chat-store-rust-bridge-allowlist-tranche.md" --format text`

## Note
- questa tranche non riclassifica `StoreRuntime/ChatStoreStreaming.swift`, che resta backlog reale del dominio `Chat`
- il prossimo target consigliato resta il drenaggio di ownership runtime residua in `Runtime` oppure `Chat/Support/StoreRuntime`
