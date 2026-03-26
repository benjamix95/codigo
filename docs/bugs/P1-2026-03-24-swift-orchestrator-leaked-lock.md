# P1 — Lock acquisition timeout non garantisce che il lock non sia stato acquisito

## Bug Fix Record
- Categoria: B - Importante
- Bug: In `OrchestratorMainLoop+Scheduling.swift`, il task group per l'acquisizione del lock usa un timeout. Se il timeout scatta, `cancelAll()` cancella il task di lock. Ma se `lockManager.acquire` non controlla `Task.isCancelled`, il lock potrebbe essere acquisito dopo il timeout e mai rilasciato.
- Sintomo: Lock leaked → task futuri non possono acquisire lo stesso lock → deadlock progressivo.
- Impatto: Deadlock dell'orchestratore dopo timeout di lock.
- Gravità: P1
- Strategia di fix minimo: Dopo `cancelAll()`, verificare se il lock è stato acquisito e rilasciarlo esplicitamente. Oppure far controllare `Task.isCancelled` dentro `lockManager.acquire`.
- Commit previsto: `fix(orchestrator): ensure lock release on acquisition timeout`
