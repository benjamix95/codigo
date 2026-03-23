# 2026-03-23 — Main chat reasoning fallback limited to test-only path

## Cosa cambia

- nel dominio reasoning della main chat i fallback Swift non sono più il path implicito standard;
- `RustMainChatCLIAccountSnapshots.swift` consente il fallback locale solo quando il bootstrap Rust è esplicitamente deferito in ambiente XCTest;
- fuori da quel caso:
  - `shouldUpdateInlineReasoningState` fallisce chiuso su `false`
  - `ChatReasoningPresentationPolicy.mode` usa solo il risultato Rust o il default conservativo
  - `ChatReasoningStreamReducer.apply` non prova più a simulare localmente il reducer del core Rust

## File toccati

- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatCLIAccountSnapshots.swift`

## Ownership

- il core Rust resta l’unico owner standard della reasoning policy della main chat;
- il fallback Swift resta solo come supporto esplicito per i test quando il core viene deferito in XCTest;
- questo riduce un’altra zona di ownership ibrida residua nel boundary host-side.

## Verifica

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatReasoningStreamReducerTests`

## Avanzamento piano

- tranche 1 completata
- tranche 2 completata
- tranche 3 completata
- tranche 4 quasi chiusa
- avanzamento complessivo: `92%`
