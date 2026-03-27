# Todo Pipeline Bugs — 2026-03-27

## Priorità A — Follow-up finali applicati fuori contesto

### Bug Fix Record
- Categoria: A — Critico
- Bug: i task `Code Review & Test` / `Doc Writer` potevano mutare la checklist canonica del piano anche quando il piano non li prevedeva.
- Sintomo: completion o `todo_write` di reviewer/testWriter/docWriter facevano avanzare o completare step canonici non correlati.
- Impatto: ordine di esecuzione incoerente, salti di step, comparsa di follow-up fuori logica.
- Gravità: alta
- Steps to reproduce:
  1. creare un piano con un solo step canonico reale, senza follow-up finali
  2. inviare un `taskCompleted` reviewer oppure un `todo_write` con titolo `Code Review & Test`
  3. osservare l’avanzamento della checklist canonica
- Risultato attuale: il fallback completava lo step canonico corrente anche senza follow-up nel piano.
- Risultato atteso: reviewer/testWriter/docWriter devono aggiornare la checklist canonica solo se il piano contiene davvero il follow-up corrispondente.
- Causa probabile: fallback canonico troppo permissivo in `PipelineIntegrationService` e negli handler dei `todo_write` di piano.
- Scope consentito: gating follow-up in `PipelineIntegrationService`, `ChatPanelView` e `TodoStore`.
- Non-scope: modifica del parser dei plan option o del renderer UI dei todo.
- Moduli confinanti da verificare: `PipelineIntegrationService`, `TodoStore`, `ChatPanelView+PartF_TodoEvents`.
- Test da aggiungere o aggiornare: regressioni per reviewer senza follow-up canonico e per raw `todo_write` senza entry canonica.
- Strategia di fix minimo: introdurre gating esplicito dei follow-up rispetto ai canonical todo del piano.
- Verifica post-fix: test `PipelineIntegrationServiceTests` verdi.
- Commit previsto: `fix(todo): gate canonical follow-up completion and preserve completed items`

## Priorità B — I completed sparivano dalla lista todo

### Bug Fix Record
- Categoria: B — Importante ma non bloccante
- Bug: i clear/reset dei todo agent rimuovevano anche i todo `done`.
- Sintomo: i todo completati sparivano invece di restare visibili barrati.
- Impatto: perdita di visibilità sul lavoro concluso e UX incoerente.
- Gravità: media
- Steps to reproduce:
  1. completare un todo agent
  2. generare un clear/reset di nuova esecuzione
  3. osservare la lista todo
- Risultato attuale: i completed venivano rimossi.
- Risultato atteso: i completed devono restare nella lista con strikethrough.
- Causa probabile: `clearAgentTodos` / `clearCanonicalAgentTodos` rimuovevano indiscriminatamente i todo agent in scope.
- Scope consentito: lifecycle store dei todo.
- Non-scope: redesign del componente grafico todo.
- Moduli confinanti da verificare: `TodoStore+Mutations+Lifecycle`, viste todo che già usano `strikethrough`.
- Test da aggiungere o aggiornare: regressioni store per preservare i completed nei clear.
- Strategia di fix minimo: preservare i todo `done` durante i clear standard.
- Verifica post-fix: `TodoStoreTests` verdi.
- Commit previsto: `fix(todo): gate canonical follow-up completion and preserve completed items`

## Priorità B — Follow-up runtime impliciti troppo aggressivi

### Bug Fix Record
- Categoria: B — Importante ma non bloccante
- Bug: il path runtime poteva inserire implicitamente `Code Review & Test` e `Doc Writer` senza richiesta esplicita del piano/esecuzione.
- Sintomo: comparsa di follow-up anche quando non c’erano veri todo finali richiesti.
- Impatto: checklist rumorosa e ordine percepito come scorretto.
- Gravità: media
- Steps to reproduce:
  1. emettere un runtime `todo_write` di una task mutativa
  2. osservare la lista todo runtime
- Risultato attuale: venivano considerati follow-up impliciti.
- Risultato atteso: i follow-up runtime devono comparire solo se emessi esplicitamente o previsti dal piano canonico.
- Causa probabile: injection automatica nel branch runtime di `handleTodoWriteEvent`.
- Scope consentito: policy follow-up runtime e call-site ChatPanel.
- Non-scope: cambio della regola dei follow-up canonici del piano.
- Moduli confinanti da verificare: `TodoExecutionFollowUpPolicy`, `ChatPanelView+PartF_TodoEvents`.
- Test da aggiungere o aggiornare: regressione su `implicitRuntimeFollowUpTitles`.
- Strategia di fix minimo: disabilitare l’injection runtime implicita e mantenere solo path espliciti/canonici.
- Verifica post-fix: `TodoExecutionRuntimeFollowUpTests` verdi.
- Commit previsto: `fix(todo): gate canonical follow-up completion and preserve completed items`
