# P1 - Le mutazioni fallback dello snapshot nel review panel passavano ancora da logica Swift locale

## Bug Fix Record
- Categoria: A
- Bug: quando il panel non poteva usare una sessione live (`ReviewSessionRegistry`), le mutazioni fallback dello snapshot (`dismiss`, `apply_fix`) venivano applicate da `CodeReviewPanelStore+SnapshotMutation.swift` con logica locale Swift invece che attraverso il reducer Rust gia' usato dal command loop.
- Sintomo: il panel e il command loop avevano ancora due path diversi per mutare finding/events nello snapshot review.
- Impatto: rischio di drift semantico tra panel e command bus su `status`, eventi emessi e aggiornamento dell'outcome, soprattutto nei fallback non-live.
- Gravita': alta, perche' tocca command boundary e stato review condiviso.
- Steps to reproduce:
  1. Aprire il panel su una sessione review non live.
  2. Eseguire una dismiss o un apply fix fallback.
  3. Osservare che il panel muta direttamente `findings/events` in Swift anziche' usare `review_core_command_mutate_snapshot`.
- Risultato attuale: il panel usava un mutator locale Swift per i fallback snapshot.
- Risultato atteso: il panel deve usare lo stesso mutator Rust del command loop per mantenere un'unica semantica di mutazione.
- Causa probabile: il bridge Rust del command loop esisteva gia', ma non era stato riutilizzato nel panel store.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+SnapshotMutation.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+Launch.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+TargetedFix.swift`
  - test panel mirati
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - mutazioni delle sessioni live
  - patch workflow completo
  - UI SwiftUI
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - `review_command::mutator` Rust tests
- Test da aggiungere o aggiornare:
  - regressione panel su dismiss fallback con `wont_fix`
  - build/test mirato su `CodeReviewPanelSessionScopingTests`
- Strategia di fix minimo:
  - introdurre una request/response panel-specifica verso `review_core_command_mutate_snapshot`
  - rimpiazzare le mutation closure Swift nel panel fallback con chiamate al reducer Rust
  - mantenere invariata la semantica osservabile del panel
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`
  - la compilazione passa; il run resta esposto ai problemi ambientali Xcode/LaunchServices gia' presenti
- Commit previsto: `refactor(review-panel): use rust snapshot mutator for fallback commands`
