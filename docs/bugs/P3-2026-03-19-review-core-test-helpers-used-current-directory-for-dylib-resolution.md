# P3 - Gli helper di test del review core usavano `currentDirectoryPath` per risolvere la dylib Rust

## Bug Fix Record
- Categoria: C
- Bug: più suite `SoloCodeAppTests` costruivano `SOLOCODE_REVIEW_CORE_LIBRARY_PATH` partendo da `FileManager.default.currentDirectoryPath`, valore fragile sotto `xcodebuild`.
- Sintomo: test review panel `skip` nonostante la dylib Rust fosse presente nel repository.
- Impatto: copertura Rust panel-side incompleta e falsi negativi nella validazione.
- Gravità: P3
- Steps to reproduce:
  1. Eseguire `xcodebuild test` sulle suite review panel che chiamano `requireReviewCore()`.
  2. Osservare `XCTSkip("Rust review core non disponibile in ambiente.")`.
- Risultato attuale: il path al dylib dipende dalla working directory del processo test.
- Risultato atteso: il path al dylib deriva dal percorso del file test, con fallback `Native/target/debug` -> `Native/RustCore/build/lib`.
- Causa probabile: helper duplicati nati in contesti in cui il cwd del processo era il root repo.
- Scope consentito:
  - `Tests/SoloCodeAppTests/*Review*`
  - `Config/validation/rust-cutover-swift-allowlist.txt`
- Non-scope:
  - runtime app
  - produzione
- Moduli confinanti da verificare:
  - `ReviewPanelProviderSelectionTests`
  - `ReviewPanelLifecycleE2ETests`
  - `CodeReviewPanelLiveRunExecutionTests`
- Test da aggiungere o aggiornare:
  - helper condiviso `ReviewCoreLibraryPathSupport.swift`
- Strategia di fix minimo:
  - introdurre helper condiviso basato su `#filePath`
  - aggiornare le suite review panel che chiamano `requireReviewCore()`
- Verifica post-fix:
  - `xcodebuild test ... -only-testing:SoloCodeAppTests/ReviewPanelGitContextTests ...`
- Commit previsto: `test(review): stabilize rust dylib path resolution in app-side suites`

## Esito
- aggiunto helper test condiviso per il path del review core Rust
- eliminate le dipendenze da `currentDirectoryPath` nelle suite review panel toccate
- i test Git context vengono eseguiti davvero, senza `skip`
