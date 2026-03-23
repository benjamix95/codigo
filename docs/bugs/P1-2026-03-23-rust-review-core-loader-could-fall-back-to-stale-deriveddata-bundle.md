# P1 - Il loader del review core Rust poteva cadere su una dylib di un altro DerivedData

## Bug Fix Record
- Categoria: A
- Bug: il bootstrap del review core Rust scandiva tutti i `DerivedData/Solo_Code-*` e, dopo un `dlopen` fallito sul bundle corrente, poteva caricare `libsolocode_rust_core.dylib` da un altro build output non correlato.
- Sintomo: nei log l’app tentava `dlopen` sul bundle corrente con errore `code signature does not cover entire file`, poi proseguiva con `Rust dylib: LOADED from .../DerivedData/...` puntando a un altro `Solo Code.app`.
- Impatto: runtime Rust non deterministico, rischio di usare ABI/codice stale rispetto all’app in esecuzione, masking di problemi reali di packaging/signing del bundle corrente.
- Gravità: P1
- Steps to reproduce:
  1. Avere almeno due cartelle `DerivedData/Solo_Code-*` con bundle app buildati.
  2. Rendere non caricabile la dylib nel bundle corrente oppure lasciarla in stato transitorio/non firmato correttamente.
  3. Avviare l’app e osservare i log del bootstrap Rust.
  4. Verificare che il loader salti il bundle corrente e carichi una dylib da un altro `DerivedData`.
- Risultato attuale: il runtime app-side poteva continuare il bootstrap con una libreria di un’altra build, mentre lo script di packaging non falliva chiuso quando il bundle richiedeva esplicitamente la dylib ma la toolchain Rust non era disponibile.
- Risultato atteso: l’app deve usare solo il proprio bundle o path espliciti; il packaging del bundle deve copiare la dylib in modo atomico, rifirmarla e fallire chiuso quando non può produrla.
- Causa probabile:
  - fallback troppo permissivo del loader Swift su tutti i `DerivedData`
  - copy della dylib nel bundle senza hardening dedicato
  - script bash non fail-closed nel caso “bundle richiesto ma toolchain assente”
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchFFIClient.swift`
  - `scripts/build_rust_search_backend.sh`
  - `Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift`
  - `Tests/SoloCodeAppTests/AppBundle/AppBundleRustReviewCoreScriptTests.swift`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - refactor generale del bootstrap Rust
  - modifica dei path di test/app non coinvolti nel caricamento della dylib
  - warning SwiftUI `onChange(of: Int)` emerso nello stesso log
- Moduli confinanti da verificare:
  - `ReviewCoreBridge.loadedState()`
  - script `build_rust_search_backend.sh`
  - packaging bundle `Contents/MacOS/solocode_rust`
- Test da aggiungere o aggiornare:
  - test unitari sulla policy di fallback `DerivedData`
  - smoke test script-side per fail-closed senza toolchain
  - smoke test script-side per copy + `codesign --verify` della dylib bundle
- Strategia di fix minimo:
  - disabilitare il fallback globale su `DerivedData` quando il processo gira già dentro un `.app`
  - mantenere il fallback solo per ambienti non app-bundle o con path espliciti
  - rendere atomica la copia della dylib e rifirmarla ad-hoc nel path di destinazione
  - far fallire lo script quando il bundle richiede la dylib ma `cargo/rustc` non sono disponibili
- Verifica post-fix:
  - smoke script fail-closed:
    - `PATH=/usr/empty HOME=<fake-home> SRCROOT=/Users/benjaminstoica/SoloCode CONFIGURATION=Debug SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR=<tmp>/Solo Code.app/Contents/MacOS/solocode_rust /bin/bash scripts/build_rust_search_backend.sh`
  - smoke script copy/sign:
    - `SRCROOT=/Users/benjaminstoica/SoloCode CONFIGURATION=Debug SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR=<tmp>/SoloCode.app/Contents/MacOS/solocode_rust /bin/bash scripts/build_rust_search_backend.sh`
    - `codesign --verify --verbose=4 <tmp>/SoloCode.app/Contents/MacOS/solocode_rust/libsolocode_rust_core.dylib`
  - test scheme tentato ma bloccato da errore preesistente in `UsageFooterContextProgressTests.swift` (`IndexingProgress` init inaccessibile)
- Commit previsto: `fix(rust): harden review core loader and bundle copy`

## Esito
- il loader non scandisce più i `DerivedData` globali quando gira già dentro un bundle `.app`
- lo script di build del review core:
  - fallisce chiuso quando il bundle richiede la dylib ma la toolchain Rust non è disponibile
  - copia la dylib in modo atomico
  - rifirma la dylib copiata prima di renderla disponibile nel path finale
- aggiunta copertura automatica lato `CoderEngineTests` e riallineato il test app-side equivalente
