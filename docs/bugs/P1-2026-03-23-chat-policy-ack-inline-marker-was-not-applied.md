# Bug Fix Record
- Categoria: A
- Bug: il marker inline `policy_ack` emesso nel testo della chat o nei delta del pipeline non veniva applicato allo stato di policy del turno.
- Sintomo: la chat mostrava `[Policy error] Required AGENTS/SKILL acknowledgment did not arrive before queued operational events could be applied.` anche quando la risposta o i delta del pipeline contenevano `[CODERIDE:policy_ack|hash=...]`.
- Impatto: turni validi venivano marcati come falliti, con eventi operativi accodati ma mai flushati.
- Gravità: alta
- Steps to reproduce:
  1. Avviare un turno con `agentsHardBlockEnabled = true` e un hash policy atteso.
  2. Fare emettere al provider il marker inline `[CODERIDE:policy_ack|hash=...]` nel testo della risposta.
  3. Fare arrivare uno o più eventi operativi soggetti a `requiresPolicyAck`.
- Risultato attuale: il testo veniva ripulito per la UI o accumulato nel pipeline, ma il marker inline non sbloccava `policyAckBlockedQueue`.
- Risultato atteso: il marker inline valido aggiorna `policyAckStateByMessage` e flusha subito la coda.
- Causa probabile: i path `onText` e `agentPipeline` accumulavano marker CoderIDE senza convertire `policy_ack` in un ack applicabile al lifecycle del turno.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift`
  - `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift`
  - `Tests/SoloCodeAppTests/ChatStreamFailureHandlingTests.swift`
- Non-scope:
  - provider policy engine
  - finalizzazione ritardata dei turni
  - refactor dei binding chat
- Moduli confinanti da verificare:
  - parser marker inline
  - flush della coda policy ack
  - sanitizzazione testo streammato
- Test da aggiungere o aggiornare:
  - test di regressione sul parser dei marker inline `policy_ack`
- Strategia di fix minimo:
  - estrarre gli hash `policy_ack` dal testo streammato
  - applicare l’ack una sola volta prima della sanitizzazione UI
  - ripetere lo stesso riconoscimento sul testo cumulativo dei task pipeline per gestire marker spezzati sui `textDelta`
  - flushare la coda se l’hash è valido
- Verifica post-fix:
  - test unitari sul parser
  - build/test mirati della suite `SoloCodeAppTests`
- Commit previsto: `fix(chat): consume inline policy ack markers before sanitizing stream text`
