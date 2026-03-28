# P2 - Il gate todo-first bloccava il primo command_execution anche con auto-todo gia' avviato

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il gate `todo_first_required` ignorava il placeholder auto-todo gia' avviato dal runtime e continuava a bloccare il primo `command_execution` del turno.
- Sintomo: durante il lancio di un task appariva il banner `Todo required before execution`, anche se il sistema aveva gia' creato un todo operativo temporaneo.
- Impatto: falsi positivi di policy e interruzione del task all'avvio.
- Gravita': P2
- Steps to reproduce:
  1. Avviare un task in modalita' agent con auto-todo runtime attivo.
  2. Far arrivare un `turn_started` seguito da `command_execution`.
  3. Osservare il blocco `todo_first_required`.
- Risultato attuale: il gate considerava solo `didSeeTodoWrite` e non il placeholder auto-todo.
- Risultato atteso: un auto-todo runtime attivo deve soddisfare il requisito di todo iniziale per non bloccare il primo comando operativo.
- Causa probabile: disallineamento tra il runtime auto-todo e la policy di avvio eseguita su `command_execution`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+PolicyHelpers.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyTodoFlush.swift`
  - `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
  - documentazione collegata
- Non-scope:
  - routing dei tool
  - provider Codex
  - plan runtime
- Moduli confinanti da verificare:
  - auto-todo runtime
  - policy `todo_first_required`
  - task launch flow
- Test aggiunto:
  - `ChatTodoVisibilityTests.testTodoPlanStartPolicyAllowsCommandExecutionWhenAutoTodoRuntimeIsActive`
- Strategia di fix minimo:
  - considerare l'auto-todo runtime come soddisfacente per il gate `todo_first_required`
  - lasciare invariato il resto del flusso di task/plan
- Verifica post-fix:
  - test unitario mirato sul gate todo-first
- Commit previsto:
  - `fix(chat): let auto todo runtime satisfy the todo-first gate`

