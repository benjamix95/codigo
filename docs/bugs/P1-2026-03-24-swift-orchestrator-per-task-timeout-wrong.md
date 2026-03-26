# P1 — Per-task timeout = jobTimeout / totalTaskCount errato per workload paralleli

## Bug Fix Record
- Categoria: B - Importante
- Bug: `OrchestratorMainLoop` calcola `perTaskTimeoutMs = max(job.jobTimeoutMs / taskCount, 30_000)`. Con molti task paralleli, il timeout per-task diventa troppo breve.
- Sintomo: Task legittimi vengono terminati prematuramente quando il job ha molti task.
- Impatto: Risultati incompleti, task importanti non completati.
- Gravità: P1
- Strategia di fix minimo: Dividere per il numero di task concorrenti (max parallelism), non per il totale. O usare un timeout per-task fisso + un timeout globale per il job.
- Commit previsto: `fix(orchestrator): calculate per-task timeout based on parallelism not total count`
