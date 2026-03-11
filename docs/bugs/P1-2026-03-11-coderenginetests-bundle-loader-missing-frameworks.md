# P1 - `CoderEngineTests.xctest` non caricabile per framework mancanti nel bundle test

## Bug Fix Record
- Categoria: A - Critico
- Bug: il bundle `CoderEngineTests.xctest` non era autosufficiente e falliva il load del target engine in macOS.
- Sintomo: `xcrun xctest` e `xcodebuild test` sul target engine fallivano con `Library not loaded: @rpath/CoderEngine.framework/...`.
- Impatto: i test `CoderEngineTests` non erano eseguibili in modo affidabile; il problema veniva confuso con errori di codesign/policy.
- Gravità: alta, blocca regressioni su persistence/shared-state/review core.
- Steps to reproduce:
  1. eseguire `xcrun xctest <DerivedData>/Build/Products/Debug/CoderEngineTests.xctest`
  2. osservare il failure sul load di `@rpath/CoderEngine.framework`
- Risultato attuale: il bundle test non embedda `CoderEngine.framework` e `CoderIDEMCPServer.framework`, e i prodotti test possono mantenere xattr `com.apple.provenance`.
- Risultato atteso: il bundle `CoderEngineTests.xctest` deve embeddate i framework runtime richiesti e risultare caricabile via scheme dedicato.
- Causa probabile: confermata. Il progetto generato non aggiungeva una `Embed Frameworks` phase a `CoderEngineTests`; inoltre mancava un bootstrap repo-local per sanitizzare/rifirmare i bundle test.
- Scope consentito: `scripts/generate_xcode_project.rb`, scripts di harness test, test struttura progetto, scheme condivisi generati.
- Non-scope: codice business review, UI app, provider runtime.
- Moduli confinanti da verificare: `scripts/solocode-validate`, `Solo Code.xcodeproj`, `Solo Code.xcworkspace`, scheme test condivisi.
- Test da aggiungere o aggiornare:
  - regressione su struttura progetto/scheme
  - smoke test engine con scheme dedicato
- Strategia di fix minimo:
  - embed dei framework richiesti in `CoderEngineTests`
  - script repo-local `bootstrap_test_bundles.sh`
  - pre-action sugli scheme test
  - scheme dedicato `CoderEngineTests-Debug`
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewFindingTests`
  - risultato: verde
- Commit previsto: tranche dedicata test harness + review command Rust mutation
