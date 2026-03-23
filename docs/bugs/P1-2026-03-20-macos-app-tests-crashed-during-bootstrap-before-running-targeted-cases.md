# P1 - I test app-side macOS crashano durante il bootstrap prima di eseguire i casi mirati

## Bug Fix Record
- Categoria: A
- Bug: l'esecuzione `xcodebuild test` per i target app-side termina con `Early unexpected exit, operation never finished bootstrapping`, impedendo l'avvio dei test mirati.
- Sintomo:
  - build e codesign completano
  - il runner lancia `Solo Code`
  - la sessione test termina con crash del runner prima dell'esecuzione dei casi richiesti
- Impatto: blocco della validazione automatica app-side, inclusi i test di regressione necessari per il cutover `main chat`.
- Gravita': alta, perche' impedisce la verifica dei path UI/runtime che dipendono dall'avvio dell'app.
- Steps to reproduce:
  1. Eseguire `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`.
  2. Attendere il completamento della build.
  3. Osservare l'uscita con `code 65` e messaggio `Early unexpected exit, operation never finished bootstrapping`.
- Risultato attuale: i test non partono.
- Risultato atteso: i test mirati devono eseguire davvero i casi `ChatPipelineReducerTests` e `PipelineIntegrationServiceTests`.
- Causa probabile: crash di bootstrap app-side non legato alla compilazione del bundle test; possibile instabilita' di startup o dipendenza runtime del target `Solo Code`.
- Scope consentito:
  - bootstrap app-side macOS
  - target `Solo Code`
  - configurazione runner test
  - documentazione bug/changelog
- Non-scope:
  - logica del reducer Rust `main_chat`
  - boundary `rust_cutover_guard`
- Moduli confinanti da verificare:
  - `SoloCodeApp`
  - servizi bootstrap dell'app
  - eventuali script build-phase Rust
- Test da aggiungere o aggiornare:
  - smoke test affidabile di bootstrap app-side
  - eventualmente test runner dedicated per target app
- Strategia di fix minimo:
  - isolare il crash di bootstrap fuori dal lavoro di migrazione `main chat`
  - ripristinare un path affidabile per esecuzione `SoloCodeAppTests`
- Verifica post-fix:
  - stessa invocazione `xcodebuild test` sopra, senza `Early unexpected exit`
- Commit previsto: `fix(testing): restore app-side bootstrap for macOS test runner`

## Effetto osservato
- La build dei target toccati completa, ma la validazione test app-side resta bloccata a causa del crash del runner.
