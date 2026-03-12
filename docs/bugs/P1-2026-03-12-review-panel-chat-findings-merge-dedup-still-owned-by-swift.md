# P1 - Il merge/dedup dei finding strutturati estratti dalla chat review era ancora panel-owned in Swift

## Bug Fix Record
- Categoria: A
- Bug: dopo l'estrazione del blocco `review_findings`, il panel applicava ancora in Swift il merge e la deduplica dei finding sullo snapshot review.
- Sintomo: il path chat -> findings tab manteneva un reducer locale Swift per dedup e count degli inserimenti, invece di delegare al core Rust.
- Impatto: rischio di drift tra path panel chat e resto del review core, soprattutto su deduplica e normalizzazione del merge.
- Gravita': alta, perche' tocca il boundary tra chat review e snapshot canonico.
- Steps to reproduce:
  1. Iniettare nel panel un messaggio con blocco `review_findings`.
  2. Sincronizzare i finding nella tab Findings.
  3. Ripetere lo stesso finding e verificare che il dedup avveniva ancora via chiave Swift locale.
- Risultato attuale: deduplica e merge dei finding chat erano gestiti nel panel store.
- Risultato atteso: il core Rust deve poter decidere merge e count degli inserimenti; Swift deve restare adapter/fallback.
- Causa probabile: la migrazione review-side aveva coperto snapshot/history/command boundary, ma non il sottopath chat findings -> snapshot.
- Scope consentito:
  - `Native/RustCore/src/review_chat.rs`
  - `Native/RustCore/src/ffi/review_core.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustChatFindings.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - parsing del blocco markdown `review_findings`
  - UI del tab Chat
  - mutazioni live session
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - test Rust `review_chat`
- Test da aggiungere o aggiornare:
  - unit test Rust su dedup `merge_chat_findings`
  - test panel scoping esistente per sync/dedup finding da chat
- Strategia di fix minimo:
  - introdurre reducer Rust `merge_chat_findings`
  - aggiungere adapter Swift stretto
  - mantenere fallback Swift solo se il bridge Rust non e' disponibile
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`
  - build/test compilation pass; esecuzione suite ancora soggetta ai problemi ambientali LaunchServices/Xcode della sessione
- Commit previsto: `refactor(review-panel): route chat findings merge through rust`
