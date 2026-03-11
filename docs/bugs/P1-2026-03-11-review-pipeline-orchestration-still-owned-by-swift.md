# P1 — La pipeline del code review era ancora orchestrata da Swift, con stato e flusso distribuiti su più helper

## Bug Fix Record
- Categoria: A
- Bug: il run della review continuava a dipendere dal coordinator Swift per parsing scope, round loop, task extraction, re-review e gestione della sessione, nonostante il review core Rust fosse già introdotto per audit/verifica/projection.
- Sintomo: la pipeline era divisa tra Rust e Swift, con rischio di drift semantico, più punti di decisione e maggiore fragilità nelle aree `cancel/pause/review state`.
- Impatto: alta probabilità di regressioni future nella review pipeline e maggiore costo di manutenzione; il pannello osservava uno stato non canonico unico.
- Gravita': alta, perché tocca orchestration e state management condiviso.
- Steps to reproduce:
  1. Avviare una review dal panel o dal command loop.
  2. Seguire il flusso `ReviewPipelineCoordinator -> CodeReviewMultiSwarmProvider -> SessionState`.
  3. Osservare che il motore Rust non possiede il loop e che Swift conserva la business logic principale.
- Risultato attuale: il coordinator Swift deve limitarsi a fare da driver/adapter e il flusso principale deve essere deciso dal motore Rust.
- Risultato atteso: la review end-to-end parte da Swift ma viene governata da uno state machine canonico Rust, con snapshot riconciliato nel `CodeReviewSessionState`.
- Causa probabile: migrazione precedente limitata ai soli hot path compute, senza il passaggio successivo dell’orchestrazione.
- Scope consentito:
  - `Native/RustCore/src/review_pipeline/*`
  - `Native/RustCore/src/ffi.rs`
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/*`
  - `Engine/CoderEngine/Sources/CodeReview/Session/CodeReviewSessionState.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI SwiftUI e store panel
  - patch workflow/apply/merge
  - provider factory e wiring UI
- Moduli confinanti da verificare:
  - `ReviewPipelineCoordinatorTests`
  - `CodeReviewMultiSwarmProviderTests`
  - `PipelineIntegrationVerifiedFindingsTests`
  - `ReviewPanelFindingsHistoryTests`
- Test da aggiungere o aggiornare:
  - unit test Rust su parsing scope/tasks e outcome classification
  - test Swift del coordinator no-file path sul driver Rust
  - regressioni app-side che osservano snapshot review/history
- Strategia di fix minimo:
  - introdurre un motore step-based in Rust con session store canonico
  - fare eseguire a Swift solo callback runtime e riconciliazione snapshot
  - lasciare i helper Swift esistenti come adapter temporanei, non come orchestratore primario
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- Commit previsto: `perf(review): move review pipeline orchestration into rust core`
