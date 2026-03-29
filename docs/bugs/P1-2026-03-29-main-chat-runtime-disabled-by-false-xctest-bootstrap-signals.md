# P1 - Il bootstrap Rust della main chat si disattivava per falsi segnali XCTest

## Bug Fix Record
- Categoria: A
- Bug: `ReviewCoreBridge.isEnabled` poteva risultare `false` in una normale esecuzione dell'app, facendo fallire chiusa la risoluzione del provider runtime della main chat per qualunque LLM.
- Sintomo:
  - invio messaggi fallito con:
    - `[Runtime] Rust transport unavailable for main chat provider resolution. Standard path is fail-closed outside XCTest or explicit rollback flags.`
    - `[Error] Unable to resolve runtime provider for this mode.`
- Impatto: tutta la chat principale diventava inutilizzabile nel path standard, anche con provider correttamente configurati e autenticati.
- Gravità: P1
- Steps to reproduce:
  1. Avviare l'app macOS in build debug normale.
  2. Inviare un messaggio con un provider qualsiasi.
  3. Osservare il fail-closed del runtime provider.
- Risultato attuale: la policy `shouldDeferRustReviewCoreBootstrap(...)` considerava anche euristiche globali (`Bundle.allBundles`, `Bundle.allFrameworks`, `NSClassFromString("XCTestCase")`) oltre ai marker espliciti di XCTest.
- Risultato atteso: il defer del review core Rust deve scattare solo con segnali XCTest espliciti o con flag di disabilitazione Rust impostati nell'environment.
- Causa probabile: build debug dell'app con artefatti XCTest presenti o caricati nel processo; le euristiche globali producevano un falso positivo e spegnevano il runtime Rust anche fuori dal vero host di test.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift`
  - `Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift`
  - `Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift`
  - `docs/bugs`
  - `CHANGELOG-2026-03-29-main-chat-runtime-xctest-bootstrap-false-positive.md`
- Non-scope:
  - transport provider Rust
  - registry provider
  - fallback legacy della main chat
  - packaging della dylib Rust
- Moduli confinanti da verificare:
  - `ReviewCoreBridge.isEnabled`
  - `shouldSkipRustStoreBootstrapForTests(...)`
  - `resolveMainChatTransportProvider(...)`
- Test da aggiungere o aggiornare:
  - regressione engine: il bootstrap Rust non deve essere deferito con environment normale
  - regressione app-side: lo store non deve trattare il launch normale come host XCTest
- Strategia di fix minimo:
  - eliminare le euristiche globali su bundle/framework/classi XCTest dalla policy di defer
  - mantenere soltanto marker espliciti dell'environment e flag di disable Rust
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCoreBootstrapPolicyTests -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests`
- Commit previsto:
  - `fix(chat-runtime): avoid false xctest bootstrap deferral`

## Esito
- la policy di bootstrap Rust usa ora solo marker XCTest espliciti dell'environment
- il launch normale dell'app non viene più classificato come host XCTest
- aggiunte regressioni mirate lato engine e app-side sul caso di environment normale
