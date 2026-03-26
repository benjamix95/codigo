# P1 — terminateProcessIfNeeded non uccide i processi figli

## Bug Fix Record
- Categoria: B - Importante
- Bug: `terminateProcessIfNeeded` in `SubagentCLIConfig.swift` invia SIGTERM/SIGINT/SIGKILL solo al PID diretto del processo CLI. I processi figli (comuni in codex/claude CLI) diventano orfani.
- Sintomo: Dopo timeout di un subagent, processi orfani continuano a girare, consumando CPU/memoria e potenzialmente scrivendo nel workspace.
- Impatto: Resource leak, possibili conflitti di scrittura.
- Gravità: P1
- Strategia di fix minimo: Usare `kill(-pgid, signal)` per terminare l'intero process group, o impostare il process group alla creazione del `Process`.
- Commit previsto: `fix(subagent): kill process group instead of single PID on timeout`
