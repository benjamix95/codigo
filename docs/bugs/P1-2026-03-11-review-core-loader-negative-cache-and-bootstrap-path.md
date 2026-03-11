# P1 — Il loader review-core Rust poteva restare in fallback per cache negativa e bootstrap path debole

## Bug Fix Record
- Categoria: A
- Bug: il loader review-core Rust si fermava facilmente sul fallback Swift quando la prima risoluzione falliva o quando il path della `.dylib` non era deducibile dal processo test.
- Sintomo: `ReviewCoreBridge.loadedState().loaded` restava `false`, `rust_review_core_loaded` nei benchmark rimaneva falso e i test Rust-bridge venivano skippati o non percorrevano davvero il path nativo.
- Impatto: la tranche Rust esisteva nel codice ma non era osservabile/validabile in modo affidabile dentro `xcodebuild`.
- Gravita': alta lato verifica del rollout, media lato runtime perche' il fallback Swift evitava crash funzionali.
- Steps to reproduce:
  1. Costruire `Native/RustCore/build/lib/libsolocode_rust_core.dylib`.
  2. Eseguire test o benchmark con loader che prova a risolvere la libreria una sola volta oppure che dipende da `currentDirectoryPath`.
  3. Osservare `library_missing` o fallback persistente.
- Risultato attuale: il loader non deve piu' fissare in modo irreversibile un esito negativo e deve esporre diagnostica leggibile.
- Risultato atteso: il backend review-core deve diventare osservabile con `loaded=true`, `version`, `libraryPath` e `failureReason` coerenti.
- Causa probabile: combinazione di cache negativa nel singleton FFI, candidate path poco robusti e differenze tra shell repo-root e processo test Xcode.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift`
  - test loader/parity `CoderEngineTests`
- Non-scope:
  - refactor del search backend legacy
  - linking statico della libreria Rust nel target app
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `SearchEngineBackendTests`
  - benchmark `ValidationPerformanceTests`
- Test da aggiungere o aggiornare:
  - smoke loader review-core con path `.dylib` forzato
  - parity replay/gate/historical shaping con bridge Rust attivo
- Strategia di fix minimo:
  - eliminare la cache negativa irreversibile
  - aggiungere stato diagnostico del loader
  - usare bootstrap path derivato dal repo nei test
- Verifica post-fix:
  - `xcodebuild test ... -only-testing:CoderEngineTests/SearchEngineBackendTests/testReviewCoreBridgeLoadedStateReturnsVersionWhenLibraryPathIsForced`
  - `xcodebuild test ... -only-testing:CoderEngineTests/VerifiedFindingsReplayServiceTests/testReplayServiceMatchesRustBridgeWhenLibraryIsAvailable`
  - `xcodebuild test ... -only-testing:CoderEngineTests/VerifiedFindingsSecurityGateServiceTests/testGateMatchesRustBridgeWhenLibraryIsAvailable`
- Commit previsto: `fix(review): make rust review-core loader observable and retryable`
