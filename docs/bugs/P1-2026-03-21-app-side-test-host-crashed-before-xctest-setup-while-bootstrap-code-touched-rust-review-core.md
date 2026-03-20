# P1 - L'host app dei test crasha prima del `setUp` XCTest se il bootstrap tocca il review core Rust

## Bug Fix Record
- Categoria: A
- Bug: l'host app `Solo Code` può crashare prima che i test app-side impostino `SOLOCODE_REVIEW_CORE_LIBRARY_PATH`, perché alcuni path di bootstrap toccano il review core Rust troppo presto.
- Sintomo: `xcodebuild test-without-building` fallisce con `Early unexpected exit` e crash report `Code Signature Invalid` durante `dlopen`.
- Impatto: la pipeline app-side non riesce a validare le suite main-chat Rust boundary, anche quando il codice della tranche compila correttamente.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire `xcodebuild test-without-building` su suite app-side che usano l'host app `Solo Code`.
  2. Osservare il crash del processo host prima dell'avvio effettivo di XCTest.
  3. Aprire il crash report `Solo Code-*.ips` e verificare lo stack su `ReviewCoreBridge.call(...)`.
- Risultato attuale: il processo host tenta di caricare la dylib Rust durante il bootstrap dell'app, prima che i test possano impostare l'ambiente dedicato.
- Risultato atteso: durante il bootstrap di XCTest l'app non deve entrare nel review core Rust; i test possono abilitarlo solo dopo il `setUp`.
- Causa probabile: bootstrap Swift ancora troppo eager su path Rust-backed (`ChatStore`/bootstrap account routing) nel processo host dei test.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Conversations/ChatStoreConversations.swift`
- Non-scope:
  - logica planning Rust
  - provider runtime di produzione
  - refactor del bootstrap account completo
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `ChatStore.createConversation`
  - bootstrap dell'host app `Solo Code`
- Test da aggiungere o aggiornare:
  - `ChatStoreRustBootstrapPolicyTests`
- Strategia di fix minimo:
  - introdurre una policy esplicita di defer del bootstrap Rust durante l'avvio dell'host XCTest
  - evitare mutation Rust-backed dello store nella creazione conversazione di bootstrap
- Verifica post-fix:
  - `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests`
  - rerun delle suite `RustMainChatUIBoundary*` app-side
- Commit previsto: `test(chat): defer rust bootstrap during xctest host launch`

## Esito
- aggiunta una policy centrale in [RustSearchFFIClient.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift) che deferisce il bootstrap Rust del review core quando l'host gira sotto XCTest senza path dylib esplicito
- allineato il fallback Swift in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift) e [ChatStoreConversations.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Conversations/ChatStoreConversations.swift)
- aggiunta regressione unitaria in [ReviewCoreBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift) e smoke app-side in [ChatStoreRustBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift)
- dopo il fix l'host `Solo Code` non crasha più nel bootstrap delle suite app-side mirate
