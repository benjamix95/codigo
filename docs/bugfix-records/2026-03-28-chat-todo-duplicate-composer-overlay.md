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

## Verifica runtime (log `989bc5` dopo iterazione 4)

- Con `composerOverlayVisible=1`, i probe sulla timeline (`hypothesisId` A) risultano `hasTaskListMarkdown=0`, `hasOrderedList=0`, `hasPlanTodoHeader=0` sui messaggi campionati; `todo_timeline_redacted` (C) conferma riduzione del payload combinato.
- Log `F`/`G` assenti se il pannello Plan non è stato aperto (`showPlanPanel` false); per la barra laterale aprire il Plan e cercare `plan_panel_env_and_todo_card_visibility` (G) con `suppressEnv=1` e `showTodoSummaryCardInScroll=0` quando l’overlay composer è attivo.

## Iterazione 5 (reasoning + probe)

- I blocchi `.reasoning` in timeline possono contenere checklist non coperte da `combinedVisibleTextualPayload` (prima: solo primary/plan/status). Ora: strip anche su `.reasoning` nel sanitizer display-only; il probe A include il testo reasoning per allineamento.

## Iterazione 6 (trace MCP todo vs overlay)

- **Sintomo**: in chat restavano righe tipo `mcp__coderide__coderide_todo_read` (feed lineare) che si aggiornano dal `ToolTraceStore`, mentre l’overlay legge `TodoStore` — due superfici sovrapposte e “vive” sullo sfondo del composer semi-trasparente.
- **Evidenza logica**: `shouldShowOperationEventInLinearChat` nasconde MCP `todo_read`/`todo_write` solo se `showTodoCard` è true (vecchia card legata a `shouldShowTodoCardInTurn`). Con overlay composer, `shouldShowTodoCardInTurn` è 0 → le righe MCP restavano visibili.
- **Fix**: `suppressInlineTodoToolTraceBecauseComposerOverlay` su `ChatTurnView` (da `isComposerTodoOverlayVisibleForCurrentConversation`), stessa unione `(shouldShowTodo && !todoItems.isEmpty) || suppress…` per il filtro trace. Sfondo **opaco** su `ComposerTodoOverlayView` per eliminare bleed-through del gradient composer. Log `composer_overlay_suppresses_inline_todo_traces` (`H`).

## Iterazione 7 (log H: `hiddenTodoTraceRows` sempre 0)

- **Evidenza**: `composer_overlay_suppresses_inline_todo_traces` mostrava `hiddenTodoTraceRows=0` ma `traceTotal > inlineAfterSuppress` — il filtro con `showTodoCard` non classificava molti eventi come todo (es. `type == "coderide_todo_read"` o `mcp_tool` con prefisso `mcp__coderide__coderide_`), quindi restavano nel feed mentre il testo sullo schermo duplicava l’overlay.
- **Fix**: strip `mcp__coderide__coderide_` / `functions.mcp__coderide__coderide_` in `normalizedTodoPolicyToolName`; in `shouldShowOperationEventInLinearChat` nascondere **sempre** qualunque evento il cui nome normalizzato sia `todo_read` o `todo_write` (parametro `showTodoCard` deprecato con default). Rimosso flag `suppressInlineTodoToolTraceBecauseComposerOverlay`. Log `linear_chat_todo_trace_rows_normalized` (`H`, `post-h2-fix`) con `todoNormalizedRowsInTrace`.

## Stato

- Instrumentazione `989bc5` lasciata attiva finché la verifica post-fix non è confermata.
