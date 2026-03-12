# P1 - La selezione dei finding da finalizzare a review completata era ancora decisa nel panel Swift

## Bug Fix Record
- Categoria: A
- Bug: `finalizeCompletedReviewSessionIfNeeded(...)` selezionava ancora in Swift i finding verificati che richiedevano `prepareVerifiedPatches`, basandosi su stato finding/patch dello snapshot.
- Sintomo: anche con review core Rust ormai owner di gran parte del panel state, la finalizzazione completata manteneva un secondo motore Swift per scegliere i target patch-finalization.
- Impatto: rischio di drift tra panel e core review su quali finding sono davvero pronti o ancora pendenti per patch preparation.
- Gravita': alta, perche' tocca il passaggio terminale tra findings verificati e patch runtime finalization.
- Steps to reproduce:
  1. Completare una review con finding verificati ma patch non ancora pronta.
  2. Eseguire `finalizeCompletedReviewSessionIfNeeded(...)`.
  3. Osservare che la selezione `targetIds` veniva ancora derivata localmente da Swift.
- Risultato attuale: i target di finalizzazione erano calcolati nel panel store.
- Risultato atteso: il core Rust deve selezionare i finding da finalizzare a review completata; Swift deve solo eseguire il runtime provider-side.
- Causa probabile: la migrazione precedente ha coperto history/chat/launch/mutations, ma non la logica terminale di auto-prepare completion.
- Scope consentito:
  - `Native/RustCore/src/review_finalize.rs`
  - `Native/RustCore/src/ffi/review_core.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustCompletionFinalization.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelProviderSelectionTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - esecuzione concreta `prepareVerifiedPatches`
  - patch workflow apply/rollback
  - UI SwiftUI
- Moduli confinanti da verificare:
  - `review_finalize` Rust tests
  - `ReviewPanelProviderSelectionTests`
- Test da aggiungere o aggiornare:
  - unit test Rust su `select_patch_finalization_targets`
  - test app-side sul reducer Rust di selezione target
- Strategia di fix minimo:
  - introdurre reducer Rust `derive_patch_finalization_targets`
  - aggiungere adapter Swift stretto
  - lasciare in Swift solo il loop di esecuzione del runtime provider per ogni target
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
  - build passa; esecuzione suite ancora bloccata da LaunchServices/Xcode in questo ambiente
- Commit previsto: `refactor(review-panel): derive completion finalization targets in rust`
