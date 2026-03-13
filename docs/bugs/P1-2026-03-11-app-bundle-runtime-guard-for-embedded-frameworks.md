# P1 — Il target app mancava di una guardia runtime contro bundle incompleti

## Bug Fix Record
- Categoria: A
- Bug: il report crash `DYLD Library not loaded: @rpath/CoderEngine.framework/...` non era protetto da una validazione repo-local del bundle app prima del launch/copy.
- Sintomo: l’app poteva essere lanciata o esportata con artefatti incompleti e fallire all’avvio con `SIGABRT` in `dyld`.
- Impatto: impossibilità di avviare l’app quando il bundle prodotto è incoerente.
- Gravità: alta.
- Steps to reproduce:
  1. costruire un bundle macOS incoerente o parzialmente aggiornato.
  2. lanciare `Solo Code.app`.
  3. osservare `Library not loaded: @rpath/CoderEngine.framework/...`.
- Risultato attuale: il progetto embedda già i framework, ma mancava una guardia esplicita prima di `open`/copy del bundle.
- Risultato atteso: gli script repo-local devono fallire subito se mancano `CoderEngine.framework`, `CoderIDEMCPServer.framework` o il link runtime atteso.
- Causa probabile: mismatch transitorio di DerivedData / bundle incoerente non intercettato dagli script di lancio/build.
- Scope consentito:
  - `scripts/run-app.sh`
  - `scripts/build-app.sh`
  - `scripts/validate_app_bundle.sh`
  - `Tests/SoloCodeAppTests/AppBundleProjectStructureTests.swift`
- Non-scope:
  - refactor del project generator
  - modifica del wiring framework nel target app senza riproduzione stabile
- Moduli confinanti da verificare:
  - script di build/lancio app
  - `AppBundleProjectStructureTests`
- Test da aggiungere o aggiornare:
  - regressione che assicura presenza dello script e guardia dell’embed runtime per `Solo Code`
- Strategia di fix minimo:
  - introdurre `validate_app_bundle.sh`
  - chiamarlo dagli script `run-app.sh` e `build-app.sh`
  - aggiungere test di struttura progetto/script per il target app
- Verifica post-fix:
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64'`
  - `scripts/validate_app_bundle.sh <Solo Code.app>`
  - `AppBundleProjectStructureTests`
- Commit previsto: `fix(build): validate app bundle before launch and export`
