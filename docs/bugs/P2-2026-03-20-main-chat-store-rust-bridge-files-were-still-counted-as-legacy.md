# P2 - I file `StoreRust` della main chat erano ancora conteggiati come legacy Swift non-UI

## Bug Fix Record
- Categoria: B
- Bug: i file sotto `App/SoloCodeApp/Sources/Chat/Support/StoreRust/**` erano gia' bridge puri verso lo store Rust della `main chat`, ma il boundary li classificava ancora come backlog Swift non-UI.
- Sintomo:
  - [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift) espone solo invocazioni `ReviewCoreBridge` e applicazione snapshot
  - [MainChatStoreBridgeModels.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/MainChatStoreBridgeModels.swift) contiene soltanto DTO `Codable` di bridge
  - [RustMainChatStoreAdapter.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift) fa solo mapping tra modelli Swift e snapshot Rust
- Impatto: il baseline strutturale `main chat` risultava gonfiato di tre file che non possiedono piu' logica business, rallentando artificialmente il progresso del cutover.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit canonico `main chat` documentato in [RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md](/Users/benjaminstoica/SoloCode/docs/migration/RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md).
  2. Cercare nel report i file `App/SoloCodeApp/Sources/Chat/Support/StoreRust/**`.
  3. Aprire i tre file e verificare che implementano solo bridge DTO/mapping/invocazione FFI.
- Risultato attuale: il boundary li considera `legacy_non_ui`.
- Risultato atteso: devono essere allowlisted come `binding_adapter`, esattamente come `StoreProjection/**` e `Providers/Rust/**`.
- Causa probabile: la tranche store ha spostato l'ownership in Rust, ma l'allowlist del cutover non e' stata aggiornata per riflettere il nuovo confine.
- Scope consentito:
  - [rust-cutover-swift-allowlist.txt](/Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt)
  - [app_core_boundary_main_chat.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/app_core_boundary_main_chat.rs)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - `StoreRuntime/ChatStoreStreaming.swift`
  - nuova migrazione store business in Rust
  - modifiche funzionali a `ChatStore`
- Moduli confinanti da verificare:
  - `rust_cutover_guard`
  - `scripts/validate_rust_cutover_boundary.sh`
  - baseline canonico `main chat`
- Test da aggiungere o aggiornare:
  - regressione Rust che prova `StoreRust/**` allowlisted sotto prefisso largo `App/SoloCodeApp/Sources/Chat` e lascia emergere il backlog nested reale
- Strategia di fix minimo:
  - aggiungere `StoreRust/**` all'allowlist come `binding_adapter`
  - coprire il caso con test Rust dedicato
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "Config/validation/rust-cutover-swift-allowlist.txt,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs" --format text`
  - `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "Config/validation/rust-cutover-swift-allowlist.txt,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs,docs/bugs/P2-2026-03-20-main-chat-store-rust-bridge-files-were-still-counted-as-legacy.md,docs/changelog/2026-03-20-main-chat-store-rust-bridge-allowlist-tranche.md" --format text`
- Commit previsto: `fix(validation): allowlist main-chat store rust bridge adapters`

## Effetto osservato
- il backlog canonico `main chat` si riduce di tre file effettivamente bridge-only
- il guard continua comunque a bloccare i file ancora business-owned sotto il prefisso largo `Chat`
- la misura strutturale torna piu' aderente al confine reale Swift shell / Rust owner
