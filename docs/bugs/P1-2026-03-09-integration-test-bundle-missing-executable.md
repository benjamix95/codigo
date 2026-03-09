# P1 - Integration test bundle non caricabile: `SoloCodeIntegrationTests.xctest` senza eseguibile

## Bug Fix Record
- Categoria: Categoria B — importante ma non bloccante
- Bug: lo scheme `Solo Code-IntegrationTests` fallisce prima di eseguire i test perché il bundle `SoloCodeIntegrationTests.xctest` non contiene un eseguibile caricabile.
- Sintomo: `xcodebuild test` termina con `Failed to load the test bundle` e `The bundle’s executable couldn’t be located`.
- Impatto: pipeline di validazione incompleta; impossibile usare la suite integration come guardia regressiva automatica.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-IntegrationTests' -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
  2. Attendere il bootstrap del test runner macOS.
- Risultato attuale: la sessione di test fallisce con codice 65 prima dell'esecuzione dei test, per bundle non caricabile.
- Risultato atteso: il bundle `SoloCodeIntegrationTests.xctest` deve contenere il proprio executable e caricare correttamente i test.
- Causa probabile: poi confermata. Il target `SoloCodeIntegrationTests` aveva la `PBXSourcesBuildPhase` vuota e nessun file dentro `Tests/SoloCodeIntegrationTests`, quindi Xcode creava il bundle `.xctest` senza generare l'eseguibile `Contents/MacOS/SoloCodeIntegrationTests`.
- Scope consentito: configurazione test target e packaging del bundle integration.
- Non-scope: fix della sidebar, refactor UI, modifiche alla logica applicativa.
- Moduli confinanti da verificare: target `SoloCodeIntegrationTests`, build settings del bundle unit-test, phase/script di embedding test.
- Test da aggiungere o aggiornare: ripristinare il caricamento del bundle e rieseguire la suite integration completa.
- Strategia di fix minimo: aggiungere un smoke test host-based reale al target `SoloCodeIntegrationTests` e collegarlo alla `Sources` phase del progetto, così da ripristinare la generazione dell'eseguibile del bundle.
- Verifica post-fix:
  1. `xcodebuild test` dello scheme `Solo Code-IntegrationTests`.
  2. Conferma che il bundle venga caricato e che i test partano davvero.
  3. Esecuzione effettiva del nuovo smoke test host-based.
- Commit previsto: `fix(tests): restore integration test bundle executable`
