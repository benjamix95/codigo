# Bug: todo duplicati (timeline chat vs composer overlay)

## Evidenza runtime (sessione `989bc5`, `pre-fix`)

- **H1**: `composerOverlayVisible=1` e sul messaggio `0428e888-...` risultano `hasTaskListMarkdown=1`, `hasPlanTodoHeader=1`, `hasOrderedList=1`, `suppressPlanArtifacts=0`, `shouldShowTodoCardInTurn=0` — duplicazione da **markdown timeline**, non dalla card Swift legacy.
- **H2**: `show=1`, `todoCount=28` in `composer_overlay_policy_mirror_989bc5` — overlay attivo come atteso.
- **H3**: `suppressPlanArtifacts=0` — il contenuto piano/todo non veniva nascosto dalla route plan-panel.

## Fix

- Copia **solo display** del messaggio assistente: se `isComposerTodoOverlayVisibleForCurrentConversation`, si applica `ChatTodoTimelineDisplaySanitizer` a `content`, `primaryTextSnapshot` e testi dei blocchi `.primaryText`, `.plan`, `.status`, `.toolTrace` (con rispetto dei fence ```).
- Rimozione: sezioni `## Todo` / `## Plan` “todo-heavy”, righe task list `- [ ]`, run di liste numerate lunghe (≥4 righe) fuori dai fence.
- Log verifica: `todo_timeline_redacted` con `runId=post-fix` quando `preCombinedLen != postCombinedLen`.

## Iterazione 3 (log: `hasOrderedList=1` residuo)

- Messaggio `0428e888-…`: dopo iterazione 2 restava `hasOrderedList=1` con `hasPlanTodoHeader=0` / `hasTaskListMarkdown=0` — liste numerate **non consecutive** o isolate.
- Fix: dopo la passata su run numerati, **`stripAllOrderedListItemLines: true`** nel solo path composer: rimuove ogni riga `^\s*\d+\.\s+\S` fuori da \`\`\` fence.

## Iterazione 2 (log post-fix ancora con segnali)

- Sul messaggio `0428e888-...` restavano `hasPlanTodoHeader=1` e `hasOrderedList=1` dopo `hasTaskListMarkdown=0`: la sezione **Plan/Piano** non veniva rimossa se non “todo-heavy”; liste numerate corte (&lt;4 righe) restavano.
- Fix: **strip incondizionato** di sezioni `#`–`###` **Plan/Piano** (come Todo); soglia run numerato **2**; task list `- [ ]` anche senza testo dopo la checkbox.

## Iterazione 4 (Plan panel + collapse composer)

- **Problema**: `TodoSummaryCardView` nel pannello Plan e `ComposerTodoOverlayView` mostravano la stessa lista; in più il collapse del composer sembrava ignorato quando i todo aggiornavano lo stato (firma cambiava e `syncComposerTodoOverlayExpansionState` azzerava il dismiss utente e forzava `expanded = true`).
- **Fix**: `EnvironmentValues.planPanelSuppressCanonicalTodoSummaryCard` impostato da `ChatPanelView` con `isComposerTodoOverlayVisibleForCurrentConversation`, letto da `PlanPanelView` per nascondere la card duplicata nello scroll; barra inferiore `x/y` resta. In `syncComposerTodoOverlayExpansionState`, se l’utente ha chiuso l’overlay (`userDismissed` valorizzato), si mantiene il collapse e si aggiorna la firma salvata invece di `clearComposerTodoOverlayUserDismissedForSelection` + auto-expand.

## Stato

- Instrumentazione `989bc5` lasciata attiva finché la verifica post-fix non è confermata.
