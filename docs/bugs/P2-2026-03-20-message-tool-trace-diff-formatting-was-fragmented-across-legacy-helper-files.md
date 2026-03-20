# P2 - Il formatting `MessageToolTrace` per diff e metadata era frammentato in helper legacy separati

## Bug Fix Record
- Categoria: B
- Bug: il cluster `MessageToolTrace` manteneva helper strettamente accoppiati divisi tra [MessageToolTraceView+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Helpers.swift) e il wrapper legacy rimosso `MessageToolTraceView+Diff.swift`.
- Sintomo: la presentation logic di diff, duration e compact preview aveva ownership sparsa, aumentando il rischio di drift e di regressioni silenziose nel cluster trace.
- Impatto: manutenzione fragile del prefisso `Chat`, riduzione strutturale bloccata e superficie legacy più ampia del necessario.
- Gravità: P2
- Steps to reproduce:
  1. Aprire il cluster `App/SoloCodeApp/Sources/Chat/MessageToolTrace/`.
  2. Verificare che gli helper `buildDiffAttributed`, `formatDuration`, `compactDetail` e `compactDiffPreview` vivano in un file separato dal resto degli helper di formatting.
  3. Osservare che il progetto Xcode e il tranche gate continuino a contare un file legacy in più senza reale separazione di responsabilità.
- Risultato attuale: gli helper di formatting diff erano distribuiti in un file separato pur essendo consumati come supporto diretto della stessa view family.
- Risultato atteso: tutti gli helper di presentation/data-formatting del trace devono vivere nello stesso modulo di supporto, sotto soglia dimensionale e con un solo punto di manutenzione.
- Causa probabile: decomposizione storica del cluster `MessageToolTrace` oltre il necessario, rimasta dopo i cutover precedenti.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Helpers.swift`
  - `App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Diff.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - `main_chat_ui`
  - `MessageToolTraceView+State.swift`
  - planning / stream runtime
- Moduli confinanti da verificare:
  - `MessageToolTraceView+Details.swift`
  - `MessageToolTraceView+EventMetadata.swift`
  - `MessageToolTraceView+Loaders.swift`
  - `MessageToolTraceMCPCamelCaseTests.swift`
- Test da aggiungere o aggiornare:
  - nessun nuovo test richiesto; regressione coperta dalla suite esistente `MessageToolTraceMCPCamelCaseTests`
- Strategia di fix minimo:
  - fondere gli helper di diff nel file `+Helpers`
  - rimuovere il file legacy separato dal progetto Xcode
  - mantenere invariati i nomi helper già usati dai test
- Verifica post-fix:
  - `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests`
  - `./scripts/validate_rust_cutover_boundary.sh ...`
- Commit previsto: `refactor(chat): consolidate message tool trace helpers`

## Esito
- gli helper diff e compact preview sono stati assorbiti in [MessageToolTraceView+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Helpers.swift)
- il file legacy `MessageToolTraceView+Diff.swift` e' stato rimosso
- il progetto Xcode e' stato riallineato al nuovo assetto
