# Changelog 2026-03-28 - Todo gate respects auto-todo runtime

- Corretto il gate `todo_first_required` in modo che non blocchi il primo `command_execution` di un turno quando l'auto-todo runtime e' gia' stato avviato.
- Il controllo `todoPlanStartPolicyViolation` ora considera anche il placeholder auto-todo come stato sufficiente per continuare l'esecuzione.
- Aggiunta una regressione in `ChatTodoVisibilityTests` per verificare che un `command_execution` passi quando il runtime auto-todo e' attivo.

