# P1 - Il `ReviewSessionRegistry` continuava a mutare le sessioni live con logica Swift locale

## Bug Fix Record
- Categoria: A
- Bug: `ReviewSessionRegistry` applicava ancora `applyFix`, `dismissFinding` e `addComment` direttamente sul `CodeReviewSessionState`, senza passare dal mutator Rust comune gia' usato in altri path panel/command.
- Sintomo: le mutazioni live del registry avevano un path semantico diverso dai fallback snapshot e dal command loop.
- Impatto: rischio di drift su stati finding/eventi tra sessioni live e snapshot canonici.
- Gravita': alta, perche' il registry e' il punto centrale delle sessioni review live.
- Steps to reproduce:
  1. Registrare una sessione live nel `ReviewSessionRegistry`.
  2. Eseguire `dismissFinding` o `addComment`.
  3. Osservare che la mutazione passava da helper Swift del `CodeReviewSessionState`.
- Risultato attuale: il registry usava ancora mutazioni Swift locali sullo state actor.
- Risultato atteso: il registry deve usare `review_core_command_mutate_snapshot`, riapplicare lo snapshot canonico allo state actor e poi registrarlo.
- Causa probabile: la migrazione precedente ha corretto i call site panel ma non il livello comune `ReviewSessionRegistry`.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodeReview/Session/ReviewSessionRegistry.swift`
  - `Engine/CoderEngine/Sources/CodeReview/Core/Pipeline/Rust/CodeReviewSessionState+RustSnapshot.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewSessionRegistryTests.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - updateConfig/live orchestration completa
  - UI SwiftUI
  - provider wiring
- Moduli confinanti da verificare:
  - `ReviewSessionRegistryTests`
  - `review_command::mutator` Rust tests
- Test da aggiungere o aggiornare:
  - regressione registry live dismiss via mutator Rust
  - regressione registry live comment via mutator Rust
- Strategia di fix minimo:
  - introdurre helper interno `mutateLiveSession(...)` nel registry
  - riusare `review_core_command_mutate_snapshot`
  - applicare lo snapshot canonico aggiornato allo state actor e registrarlo
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewSessionRegistryTests`
  - build/compile passano; esecuzione suite ancora soggetta ai problemi LaunchServices/Xcode dell'ambiente
- Commit previsto: `refactor(review-registry): route live mutations through rust`
