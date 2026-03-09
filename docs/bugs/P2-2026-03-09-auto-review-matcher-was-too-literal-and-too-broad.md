## Bug Fix Record
- Categoria: B
- Bug: il matcher automatico della main chat per review intents era troppo letterale sui prompt vaghi utili e troppo largo su alcuni falsi positivi.
- Sintomo:
  - non attivava la pipeline su richieste tipo "controlla queste modifiche e dimmi se ci sono vulnerabilità"
  - intercettava in modo scorretto prompt descrittivi come "spiegami la policy di sicurezza del progetto"
- Impatto: routing review non affidabile; parte delle richieste reali restava sul path generico, mentre alcune richieste teoriche venivano dirottate sul runtime review.
- Gravità: importante
- Steps to reproduce:
  1. Inviare in main chat un prompt vago ma orientato a diff/regressioni/vulnerabilità.
  2. Verificare che non entri nel runtime review.
  3. Inviare un prompt descrittivo sulla sicurezza senza chiedere review.
  4. Verificare che venga dirottato erroneamente.
- Risultato attuale: matching a sottostringhe troppo rigido su frasi utili e troppo permissivo su token brevi come `pr`.
- Risultato atteso: trigger su richieste review esplicite o quasi-esplicite riferite a diff/modifiche/patch; nessun hijack su domande teoriche.
- Causa probabile: heuristica a semplici `contains` senza guardrail semantici sufficienti e con token ambigui.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI`
  - test `SoloCodeAppTests/AutoCodeReviewRoutingTests`
- Non-scope:
  - modifica del runtime review shared
  - modifiche MCP o panel
- Moduli confinanti da verificare:
  - `ChatPanelView+PartH_CodeReviewModes.swift`
  - `ChatPanelView+PartL_SendMessage.swift`
  - `CodeReviewPanelValidationTests`
- Test da aggiungere o aggiornare:
  - prompt security vaghi ma validi
  - prompt bug/regressioni senza keyword `review`
  - prompt descrittivo che non deve essere hijacked
- Strategia di fix minimo:
  - passare a un matcher con segnali positivi/negativi
  - rimuovere il falso positivo sul token `pr`
  - mantenere il trigger conservativo
- Verifica post-fix:
  - `xcodebuildmcp` su `AutoCodeReviewRoutingTests`
  - `CodeReviewPanelValidationTests`
  - `PipelineIntegrationVerifiedFindingsTests`
- Commit previsto: `fix(chat): harden auto review intent matcher`
