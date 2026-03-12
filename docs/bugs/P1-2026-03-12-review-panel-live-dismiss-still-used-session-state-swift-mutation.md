# P1 - La dismiss su sessioni live nel review panel usava ancora la mutazione Swift del `CodeReviewSessionState`

## Bug Fix Record
- Categoria: A
- Bug: quando il panel operava su una sessione live registrata in `ReviewSessionRegistry`, la dismiss di un finding passava ancora da `CodeReviewSessionState.dismissFinding(...)` invece che dal mutator Rust gia' usato sui fallback snapshot.
- Sintomo: live e fallback avevano ancora due path semantici diversi per `dismiss`, con potenziale drift su eventi e stato finale.
- Impatto: rischio di divergenza tra sessione live e snapshot fallback nello stesso boundary panel.
- Gravita': alta, perche' tocca mutazioni review su sessione attiva.
- Steps to reproduce:
  1. Registrare una sessione live nel `ReviewSessionRegistry`.
  2. Eseguire `dismissFinding(...)` dal panel.
  3. Osservare che la mutazione passava da `liveState.dismissFinding(...)` e non dal reducer Rust comune.
- Risultato attuale: il live path aveva ancora una mutazione Swift dedicata.
- Risultato atteso: anche le dismiss live devono usare `review_core_command_mutate_snapshot`, poi riapplicare lo snapshot canonico allo state actor.
- Causa probabile: la migrazione precedente ha coperto il fallback snapshot, ma non il path con sessione live registrata.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/CodeReviewSessionState+RustSnapshot.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+SnapshotMutation.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - altre mutazioni live non ancora instradate via Rust
  - orchestration completa della sessione live
  - UI SwiftUI
- Moduli confinanti da verificare:
  - `CodeReviewPanelLiveMutationRustTests`
  - `CodeReviewPanelSessionScopingTests`
- Test da aggiungere o aggiornare:
  - regressione app-side su dismiss live via reducer Rust
- Strategia di fix minimo:
  - rendere applicabile dall'app lo snapshot canonico sul `CodeReviewSessionState`
  - introdurre `mutateLiveSessionUsingRust(...)`
  - usare il path Rust per la dismiss anche sulle sessioni live
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests`
  - build e compilazione passano; l'esecuzione suite resta soggetta ai problemi ambientali Xcode/LaunchServices della sessione
- Commit previsto: `refactor(review-panel): route live dismiss through rust mutator`
