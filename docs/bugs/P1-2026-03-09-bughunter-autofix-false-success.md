# P1 — BugHunter puo' dichiarare autofix riuscito senza prova finale

## Bug Fix Record
- Categoria: A
- Bug: i path `autofix_preview`, `autofix_apply` e `autofix_commit` di BugHunter possono restituire un messaggio di successo senza agganciarsi a una prova forte che il patch workflow sia davvero arrivato allo stato atteso.
- Sintomo: l'utente puo' leggere "preview prepared" o "autofix applied" anche quando il workflow patch non e' verificato in modo conclusivo.
- Impatto: falsa sicurezza, commit potenzialmente tentati su patch non realmente applicate, perdita di affidabilita' dell'automazione.
- Gravita': P1
- Steps to reproduce:
  1. Avviare un run BugHunter con finding candidabile ad autofix.
  2. Forzare una condizione in cui il patch workflow non completi davvero il path positivo.
  3. Osservare il messaggio di ritorno di BugHunter.
- Risultato attuale: BugHunter puo' restituire esito positivo dopo enqueue/process senza controllare in modo forte lo stato finale della patch.
- Risultato atteso: il successo deve essere emesso solo se la patch risulta effettivamente preparata/applicata/verificata.
- Causa probabile: orchestrazione BugHunter sopra il workflow review con controllo insufficiente dell'outcome finale.
- Scope consentito: `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Commands.swift`, servizi BugHunter correlati, patch workflow state/result.
- Non-scope: redesign complessivo di BugHunter o nuova UX.
- Moduli confinanti da verificare: `ReviewPatchWorkflowService`, `CodeReviewHandler+PatchWorkflow`, shared state BugHunter.
- Test da aggiungere o aggiornare:
  - test handler BugHunter su `autofix_preview/apply/commit`
  - test di esito negativo esplicito quando il patch workflow non raggiunge lo stato atteso
  - test che impedisca il commit se la patch non e' `applied`
- Strategia di fix minimo:
  - leggere e validare lo stato finale della patch prima di emettere successo
  - impedire il commit se `verifyStatus` o `status` non sono coerenti
  - allineare il messaggio utente all'outcome reale
- Verifica post-fix:
  - test mirati BugHunter handler
  - smoke su `bughunter_autofix_*`
  - controllo dei path di errore e rollback
- Commit previsto: `fix(bughunter): require verified patch outcome before success`
