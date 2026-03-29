# P2 - Lo skip del build Rust non ricopiava la dylib nel bundle app

## Bug Fix Record
- Categoria: B
- Bug: `scripts/build_rust_search_backend.sh` usciva subito quando l'artifact Rust era già aggiornato, senza ricopiare la dylib nel `BUNDLE_OUT` richiesto.
- Sintomo:
  - test `testBuildRustSearchBackendProducesCodesignedBundleLibrary` fallito
  - bundle app temporaneo privo di `libsolocode_rust_core.dylib` nonostante lo script restituisse successo
- Impatto: i path che si affidano alla copia della dylib nel bundle possono restare con output incompleto se il rebuild viene saltato per cache.
- Gravità: P2
- Steps to reproduce:
  1. Avere `Native/RustCore/build/lib/libsolocode_rust_core.dylib` già aggiornato.
  2. Eseguire `scripts/build_rust_search_backend.sh` con `SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR` verso un bundle vuoto.
  3. Osservare che lo script stampa `artifact gia' aggiornato, skip build`.
  4. Verificare che la dylib non sia stata copiata nel bundle richiesto.
- Risultato attuale: lo skip per cache considerava solo la ricompilazione, non la sincronizzazione degli output derivati.
- Risultato atteso: anche in caso di skip build, gli artifact già presenti devono essere ricopiati in `BUILT_PRODUCTS_DIR` e `BUNDLE_OUT` quando richiesti.
- Causa probabile: early exit prima della fase di copy verso output secondari.
- Scope consentito:
  - `scripts/build_rust_search_backend.sh`
  - `Tests/CoderEngineTests/CodeReview/ReviewCoreBootstrapPolicyTests.swift`
  - `docs/bugs`
  - `CHANGELOG-2026-03-29-main-chat-runtime-xctest-bootstrap-false-positive.md`
- Non-scope:
  - compilazione del crate Rust
  - loader Swift del review core
  - transport provider della main chat
- Moduli confinanti da verificare:
  - copy verso `BUILT_PRODUCTS_DIR`
  - copy verso `SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR`
  - codesign della dylib copiata
- Test da aggiungere o aggiornare:
  - nessun nuovo test: la regressione è già coperta da `testBuildRustSearchBackendProducesCodesignedBundleLibrary`
- Strategia di fix minimo:
  - introdurre una copia degli artifact cached verso gli output richiesti prima dell'early exit
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ReviewCoreBootstrapPolicyTests`
- Commit previsto:
  - `fix(build): copy cached rust review core into requested bundle outputs`

## Esito
- gli artifact cached vengono ora ricopiati verso bundle e prodotti build anche quando la ricompilazione viene saltata
- la regressione di packaging nel test `ReviewCoreBootstrapPolicyTests` torna verde
