# Debug Panel Clarification UI Record — 2026-03-27

## Bug Fix Record
- Categoria: B
- Bug: il debug panel non rendeva affidabili le risposte rapide `A/B/C...` e la chat mostrava integralmente le risposte inviate dal panel.
- Sintomo:
  - prompt con opzioni inline tipo `A) ... B) ... C) ...` venivano trattati come testo libero, quindi nel panel mancavano le scelte selezionabili
  - dopo la conferma, il messaggio utente in chat esponeva tutto il payload del chiarimento invece di un placeholder discreto
- Impatto:
  - UX del loop debug più lenta
  - rumore nella timeline chat
  - minore privacy/leggibilità delle risposte raccolte dal panel
- Gravità: media
- Steps to reproduce:
  1. aprire una sessione debug con `debug_request_user`
  2. inviare un prompt con opzioni inline `A) ... B) ... C) ...`
  3. osservare che il panel non mostra le opzioni rapide
  4. confermare una risposta dal panel
  5. osservare che la chat mostra l’intero contenuto della risposta
- Risultato attuale:
  - il parser riconosceva bene solo opzioni a righe separate
  - la chat usava lo stesso testo inviato all’agente come contenuto utente visibile
- Risultato atteso:
  - il panel deve riconoscere anche elenchi inline `A/B/C`
  - la chat deve mostrare solo `altro` come placeholder dopo il submit dal debug panel
- Causa probabile:
  - parser troppo restrittivo, limitato a pattern line-based
  - assenza di separazione tra payload per l’agente e testo utente mostrato in chat
- Scope consentito:
  - parser prompt debug
  - card di submit del debug panel
  - wiring submit chat per chiarimenti debug
  - test di regressione dedicati
- Non-scope:
  - redesign del protocollo `debug_request_user`
  - refactor della pipeline debug
  - modifiche al plan panel o ai tool MCP
- Moduli confinanti da verificare:
  - `DebugClarificationPromptParser`
  - `DebugPanelView+ClarificationResponseCard`
  - `ChatPanelView+DebugClarificationSubmit`
- Test da aggiungere o aggiornare:
  - parsing di opzioni inline su singola riga
  - masking del testo mostrato in chat
- Strategia di fix minimo:
  - aggiungere parsing inline senza toccare il contratto MCP
  - introdurre un payload tipizzato che separa `agentPrompt` da `chatDisplayText`
- Verifica post-fix:
  - test aggiunti per parser e composer
  - validazione globale bloccata da errore preesistente fuori scope in `PipelineIntegrationService+EventMappingSupport.swift`
- Commit previsto:
  - fix(debug-panel): parse inline clarification choices and mask chat echo

## Bugs trovati

### P1 — Opzioni inline `A/B/C` non riconosciute
- i prompt debug su singola riga con scelte letterate non venivano trasformati in opzioni selezionabili.
- Fix: parser esteso a marker inline con deduplica delle lettere.

### P1 — La chat mostrava l’intera risposta del panel
- il submit del debug panel riutilizzava il payload reale anche come messaggio utente visibile.
- Fix: nuovo payload `DebugClarificationSubmission` con `agentPrompt` separato da `chatDisplayText = altro`.

### P2 — Validazione end-to-end bloccata da errore preesistente fuori scope
- la scheme `Solo Code` non compila per `canonicalTodoCompletionRoles` privato ma letto da un altro file di `ChatPipeline`.
- Stato: non corretto in questo intervento per evitare espansione silenziosa del perimetro su file già sporchi localmente.
