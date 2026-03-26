# P1 — readDataToEndOfFile blocca dopo timeout nei subagent CLI

## Bug Fix Record
- Categoria: B - Importante
- Bug: `SubagentCLIRunner.run` in `SubagentCLIConfig.swift` usa `readDataToEndOfFile()` (Foundation sincrono bloccante) per stdout/stderr. Dopo timeout, `Task.cancel()` non interrompe questa chiamata.
- Sintomo: Dopo un timeout CLI, i task di lettura stdout/stderr possono restare bloccati indefinitamente.
- Impatto: Thread leak, risorse non rilasciate.
- Gravità: P1
- Strategia di fix minimo: Chiudere esplicitamente i file handle PRIMA di cancellare i task, o usare `availableData` in un loop con check di cancellation.
- Commit previsto: `fix(subagent): close pipe handles before cancelling read tasks on timeout`
