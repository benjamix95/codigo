# Bug Fix Record
- Categoria: A
- Bug: nel path `agent` della main chat il testo primario dell’assistente poteva non arrivare mai a `primaryTextSnapshot`, lasciando visibili solo badge/artifacts e footer streaming.
- Sintomo: `ChatTurnView` renderizza il blocco `.primaryText`, ma `text` resta vuoto mentre il turno mostra comunque activity/artifacts (`Commands executed`, status badge, footer thinking).
- Impatto: il flusso core della chat agent risulta rotto; l’utente non vede la risposta inline anche quando il task continua a produrre activity.
- Gravità: alta
- Steps to reproduce:
  1. Avviare una chat in `coderMode = .agent` con provider Codex CLI nel workspace `/Users/benjaminstoica/SoloCode`.
  2. Eseguire una richiesta che produce `assistant_update` raw e activity tool ma non popola il path `textDelta/textReplace` lato pipeline.
  3. Verificare che la UI mostri artifacts/status/footer ma il body assistant resti vuoto.
- Risultato attuale: `PipelineIntegrationService` inoltra i raw events ai badge/artifacts, ma il testo di `assistant_update` non viene proiettato nel `ChatTurnState` se il provider non ha gia' emesso `textDelta/textReplace`.
- Risultato atteso: quando arriva un `assistant_update` valido durante un turno ancora streaming, il testo dell’assistente deve apparire inline nella bubble primaria.
- Causa probabile: il fallback esisteva solo nei binding UI/store; il layer pipeline ignorava `assistant_update` come sorgente di testo primario e dipendeva esclusivamente dal path `textDelta/textReplace`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
  - `Tests/SoloCodeAppTests/PipelineIntegrationAssistantUpdateTests.swift`
  - `docs/bugs/**`
  - `docs/changelog/**`
- Non-scope:
  - parser Codex CLI
  - `AgentWorkerAdapter`
  - reducer Rust/Swift della main chat fuori dal fallback pipeline
  - renderer `ChatTurnView`
- Moduli confinanti da verificare:
  - `PipelineIntegrationService`
  - `ChatPipelineCommitter`
  - `ChatStore.updateAssistantMessagePipelineState`
- Test da aggiungere o aggiornare:
  - regressione che prova la proiezione di `assistant_update` in `primaryTextSnapshot`
  - regressione che blocca overwrite tardivi dopo `jobCompleted`
- Strategia di fix minimo:
  - proiettare `assistant_update` nel `ChatTurnState` direttamente in `PipelineIntegrationService` solo mentre il turno e' ancora streaming
  - non cambiare parser/provider o semantica degli artifacts
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationAssistantUpdateTests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests`
- Commit previsto: `fix(chat): project assistant_update into inline primary text`

