# P1 - Review panel chat desincronizzata da Findings e Timeline, con rischio di sessioni review duplicate

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la chat del pannello Code Review scrive i blocchi strutturati `review_findings` nei `candidates` invece che nei `findings` verificati e non forza il riuso della review session attiva quando usa i tool review.
- Sintomo: i finding generati dalla chat non compaiono nel tab Findings principale, la timeline del pannello non riceve eventi `finding_added` coerenti e, con più task attivi nell'area review, la chat può contribuire ad aprire sessioni review aggiuntive con timeline separate.
- Impatto: perdita di tracciabilità nel workflow review, Findings tab incoerente rispetto alla chat, timeline incompleta e maggiore rischio di frammentare l'analisi in più sessioni parallele.
- Gravità: alta lato affidabilità del pannello review, media lato stabilità applicativa generale
- Steps to reproduce:
  1. Aprire il pannello Code Review con una sessione review attiva.
  2. Nella tab Chat, ottenere una risposta assistant che termina con un blocco ` ```review_findings ... ``` `.
  3. Osservare che il tab Findings non mostra i nuovi item attesi.
  4. Osservare che la timeline non registra veri eventi `finding_added` collegati ai finding della chat.
  5. Con più attività review in corso, chiedere alla chat di interrogare o aggiornare la review e osservare la possibilità di frammentare l'output su più sessioni/timeline.
- Risultato attuale: il parser della chat converte i finding in `ReviewCandidate`, li salva in `snapshot.candidates` e aggiunge un evento `candidate_added`; il prompt della chat non impone il riuso della sessione attiva né vieta `review_start` implicito.
- Risultato atteso: i finding strutturati della chat devono entrare in `snapshot.findings`, comparire nel tab Findings, produrre eventi timeline `finding_added` e la chat deve riusare esplicitamente la sessione review attiva.
- Causa probabile: `CodeReviewPanelStore+ChatFindings.swift` aggiorna il ramo sbagliato dello snapshot; `ReviewPanelCoordinator+Prompts.swift` non passa abbastanza contesto operativo per `session_id` e `conversation_id`.
- Scope consentito: store chat del pannello review, prompt builder review chat, test pannello review, docs bug/changelog.
- Non-scope: runtime MCP globale, pipeline review principale, rendering del tab timeline, main chat agent.
- Moduli confinanti da verificare: `CodeReviewPanelStore+ChatFindings.swift`, `CodeReviewPanelStore+ChatSession.swift`, `ReviewPanelCoordinator+Prompts.swift`, test review panel.
- Test da aggiungere o aggiornare: regressione sulla sync dei finding della chat verso Findings/Timeline e copertura del prompt per il riuso della sessione attiva.
- Strategia di fix minimo: convertire il payload `review_findings` direttamente in `CodeReviewFinding`, deduplicare sui findings esistenti, appendere eventi `finding_added` e rafforzare il prompt della chat con `session_id`/`conversation_id` e divieto di `review_start` implicito.
- Verifica post-fix:
  1. Eseguire `CodeReviewPanelSessionScopingTests`.
  2. Eseguire `ReviewPanelChatStructuredContentTests`.
  3. Verificare che un finding duplicato non generi un secondo evento timeline.
- Commit previsto: `fix(review-chat): sync chat findings into findings timeline`
