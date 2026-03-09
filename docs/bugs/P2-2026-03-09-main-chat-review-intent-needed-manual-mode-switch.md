## Bug Fix Record
- Categoria: B
- Bug: nella main chat le richieste libere di review/bug hunt/security audit non attivavano automaticamente il runtime review shared; serviva passare manualmente in modalità `Code Review` o usare path dedicati.
- Sintomo: prompt come "fai una review di sicurezza del diff" o "fai bug hunt su queste modifiche" venivano eseguiti dal runtime agent generico, quindi il comportamento dipendeva dall’analisi del modello invece che dal pipeline review.
- Impatto: esperienza incoerente tra main chat e review panel; l’utente non otteneva in modo affidabile la pipeline professionale `VerifiedFindings`.
- Gravità: importante
- Steps to reproduce:
  1. Restare in main chat in modalità `Agent`.
  2. Inviare un prompt del tipo "fai una review di sicurezza del diff".
  3. Osservare che il messaggio non viene instradato automaticamente al runtime review multi-swarm.
- Risultato attuale: richiesta review eseguita nel canale generico, con uso non garantito degli strumenti review.
- Risultato atteso: intent review/bug/security riconosciuto e instradato automaticamente al provider/runtime review shared, mantenendo la chat corrente.
- Causa probabile: esisteva il runtime review shared, ma mancava il matcher di intent nella composer pipeline della main chat.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions`
  - test `SoloCodeAppTests` per routing/composer validation
- Non-scope:
  - modifica del core `VerifiedFindings`
  - redesign della composer UI
  - nuovi handler MCP
- Moduli confinanti da verificare:
  - `ChatPanelView+PartL_SendMessage.swift`
  - `ChatPanelView+PartH_CodeReviewModes.swift`
  - `CodeReviewPanelValidationTests`
  - `PipelineIntegrationVerifiedFindingsTests`
- Test da aggiungere o aggiornare:
  - matcher automatico per review/security/bug hunt
  - regressione su prompt normali che non devono essere reroutati
  - smoke su validazioni code review esistenti
- Strategia di fix minimo:
  - aggiungere un matcher leggero di intent review nella chat
  - wrappare il prompt con `ReviewPanelCoordinator.combinedPrompt`
  - impostare `preferCodeReviewRuntimeProvider` solo quando l’intento è esplicito
- Verifica post-fix:
  - `xcodebuildmcp` su `AutoCodeReviewRoutingTests`
  - `CodeReviewPanelValidationTests`
  - `PipelineIntegrationVerifiedFindingsTests`
- Commit previsto: `feat(chat): auto-route review intents to shared pipeline`
