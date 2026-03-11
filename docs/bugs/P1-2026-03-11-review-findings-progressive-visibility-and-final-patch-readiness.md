# P1 — Il panel review nascondeva finding verificati e poteva chiudere il run senza patch pronta

## Bug Fix Record
- Categoria: A
- Bug: il reducer panel pubblicava solo finding `publish-ready`, quindi i finding verificati restavano invisibili; inoltre il run standard del panel poteva terminare in `completed` senza avere ancora preparato le patch per i finding verificati e patchabili.
- Sintomo: tab `Findings` vuoto o parziale nonostante finding verificati reali; progressione percepita `6/6` incoerente con la readiness patch; azioni `apply / PR / merge` non disponibili nel path standard.
- Impatto: flusso review opaco, rischio di falsi positivi UX su completamento review, maggiore dipendenza da path deferred/command loop per vedere risultati o ottenere patch pronta.
- Gravita': alta, perché tocca orchestrazione review, contract del panel e lifecycle patch.
- Steps to reproduce:
  1. Avviare una review standard dal panel.
  2. Ottenere almeno un finding verificato senza patch preview già pronta.
  3. Osservare che il panel non lo pubblica tra i risultati visibili oppure chiude il run senza renderlo azionabile.
- Risultato attuale: il panel deve mostrare candidati live, finding verificati e finding publish-ready in bucket distinti; il completamento standard deve auto-preparare patch per i finding verificati e patchabili.
- Risultato atteso: nessun finding verificato resta nascosto; il path standard arriva a risultati azionabili senza dover passare da workflow separati.
- Causa probabile: reducer Rust/Swift centrato sul solo bucket `publish-ready` e auto-prepare patch presente solo nei path deferred/command-driven.
- Scope consentito:
  - `Native/RustCore/src/review_reduce/*`
  - `Native/RustCore/src/review_pipeline/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Findings/*`
  - test review panel correlati
- Non-scope:
  - redesign generale del panel
  - rinomina comandi MCP
  - refactor fuori da review/history
- Moduli confinanti da verificare:
  - `ReviewPanelProviderSelectionTests`
  - `ReviewPipelineCoordinatorTests`
  - `VerifiedFindingsPatchExecutionService`
  - `ReviewPersistenceRustAdapter`
- Test da aggiungere o aggiornare:
  - regressione panel per finding verificati visibili prima della patch finale
  - regressione auto-prepare patch nel path standard del panel
  - unit test Rust sul reducer bucket progressivi
- Strategia di fix minimo:
  - esporre bucket progressivi dal reducer Rust
  - auto-preparare patch nel completion path standard del panel
  - mantenere Swift come esecutore side-effect locale
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests`
- Commit previsto: `fix(review): expose progressive findings and auto-prepare final patches`
