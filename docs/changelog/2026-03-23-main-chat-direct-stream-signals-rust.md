# 2026-03-23 — Main chat direct stream lifecycle signals moved to Rust

## Cosa cambia

- il poll runtime Rust della main chat restituisce ora anche i segnali di lifecycle del direct stream:
  - `firstEvent`
  - `firstTextDelta`
  - `streamCompleted`
- `ConversationFlowCoordinator` non confronta più snapshot vecchio/nuovo per dedurre questi eventi;
- Swift resta un adapter sottile:
  - chiama il poll Rust,
  - applica il nuovo snapshot,
  - inoltra `onSignal`, `onText`, `onRaw`, `onError`,
  - aggiorna lo stato locale UI (`completed` / `error`) quando riceve gli eventi terminali.

## File toccati

- `Native/AppCoreProtocol/src/main_chat_runtime.rs`
- `Native/RustCore/src/main_chat/runtime_provider_poll.rs`
- `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift`
- `App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift`
- `Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift`

## Ownership

- il core Rust possiede ora anche la decisione su quando il direct stream ha:
  - ricevuto il primo evento,
  - ricevuto il primo testo,
  - concluso lo stream;
- Swift non mantiene più euristiche locali su quei passaggi del direct stream state machine;
- l’ownership host-side residua resta limitata al dispatch delle callback UI e alla costruzione concreta del provider transport.

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml runtime_provider_poll -- --nocapture`
- `cargo test --manifest-path Native/AppCoreProtocol/Cargo.toml --quiet`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 completata
- tranche 5 sostanzialmente chiusa sul perimetro `main chat first`
- avanzamento complessivo: `100%`
