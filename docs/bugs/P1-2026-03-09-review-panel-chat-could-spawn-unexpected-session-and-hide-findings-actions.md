## Bug Fix Record
- Categoria: A
- Bug: la chat del review panel poteva trasformare una richiesta generica di review in una nuova review session implicita, alterando la sessione selezionata e facendo sparire azioni/contesto del tab `Findings`.
- Sintomo:
  - in chat comparivano output tipo `Review task extraction failed...`
  - il tab `Findings` sembrava perdere scroll, `Fix All` e altre azioni perché il panel finiva su una sessione diversa o incoerente
- Impatto: UX instabile nel panel review; la chat influenzava il contesto della sessione corrente in modo inatteso.
- Gravità: critica
- Steps to reproduce:
  1. Aprire il review panel con una sessione attiva.
  2. Scrivere in chat una richiesta generica tipo "mi fai una review della pipeline...".
  3. Osservare che il modello tende a trattarla come start implicito di una nuova review.
  4. Verificare effetti collaterali sul tab `Findings`.
- Risultato attuale: la chat non fissava la sessione corrente e il prompt lasciava troppo margine a `review_start`.
- Risultato atteso: la chat deve reinterpretare queste richieste come analisi della sessione corrente, fissando `panelSessionId` e impedendo start impliciti salvo richiesta esplicita di nuova sessione.
- Causa probabile:
  - `sendChatMessage` non pinnava la sessione attiva nel panel
  - il prompt della review chat era troppo permissivo verso `review_start`
- Scope consentito:
  - `CodeReviewPanelStore+ChatSession.swift`
  - test `SoloCodeAppTests` per panel chat routing
- Non-scope:
  - modifica dei workflow MCP review
  - redesign del tab `Findings`
  - cambi al core `VerifiedFindings`
- Moduli confinanti da verificare:
  - `ReviewPanelLifecycleE2ETests`
  - `ReviewPatchWorkflowServiceTests`
  - persistenza sessione panel
- Test da aggiungere o aggiornare:
  - prompt normalization della review chat
  - pin della sessione corrente durante `sendChatMessage`
- Strategia di fix minimo:
  - pin di `panelSessionId` all’inizio della chat
  - prompt normalization che forza l’uso della sessione corrente e vieta `review_start` implicito
- Verifica post-fix:
  - `SoloCodeAppTests/CodeReviewPanelChatPromptRoutingTests`
  - `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
  - `SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- Commit previsto: `fix(review-panel): pin active session during chat analysis`
