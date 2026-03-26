# P0 — Timeout hardcoded 300s sovrascrive il timeout role-specific del bugHunter (3600s)

## Bug Fix Record
- Categoria: A - Critico
- Bug: `SubagentExecutionStream` in `ToolEnabledLLMProvider+SubagentExecutionStream.swift` usa un timeout hardcoded di 300 secondi (5 minuti) per tutti i subagent inline, ignorando il timeout role-specific configurato in `SubagentCLIConfig.timeout(for:)`.
- Sintomo: Il subagent bugHunter, che dovrebbe avere un timeout di 3600 secondi (1 ora) per analisi approfondite, viene terminato dopo soli 5 minuti con `SubagentTimeoutError`.
- Impatto: Il bugHunter non riesce a completare analisi complesse su codebase di grandi dimensioni. Risultati parziali e incompleti.
- Gravità: P0
- Steps to reproduce:
  1. Lanciare un subagent bugHunter inline (non via CLI).
  2. Dare un task di analisi che richiede > 5 minuti.
  3. Osservare che il subagent viene terminato a 300s con `SubagentTimeoutError`.
- Risultato attuale: Linea ~197: `Task.sleep(nanoseconds: 300_000_000_000)` — hardcoded 5 minuti per tutti i ruoli.
- Risultato atteso: Il timeout deve rispettare `SubagentCLIConfig.timeout(for: role)`:
  - explorer: 95s
  - reviewer: 95s
  - bugHunter: 3600s
  - coder: 110s
  - debugger: 110s
  - testWriter: 100s (stimato)
- Causa probabile: Il timeout hardcoded è stato aggiunto come safety net senza considerare che i ruoli hanno timeout diversi. Probabilmente un valore placeholder mai parametrizzato.
- Scope consentito: `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Subagents/ToolEnabledLLMProvider+SubagentExecutionStream.swift` — task di timeout (~linea 196-199).
- Non-scope: CLI runner timeout (quello funziona correttamente), SubagentCLIConfig, SubagentRole.
- Moduli confinanti da verificare: `SubagentExecutionSupport.swift` (messaggio errore hardcoded "5 minutes"), `ToolEnabledLLMProvider+SubagentExecution.swift` (dove il ruolo è disponibile).
- Test da aggiungere o aggiornare:
  - Test: subagent bugHunter inline non viene terminato prima di 3600s.
  - Test: subagent explorer inline viene terminato dopo ~95s.
  - Test: `SubagentTimeoutError` mostra il timeout corretto nel messaggio.
- Strategia di fix minimo: Passare il `SubagentRole` (o il timeout in secondi) alla funzione di streaming. Sostituire il 300s hardcoded con `SubagentCLIConfig.timeout(for: role)` convertito in nanosecondi. Aggiornare il messaggio di errore in `SubagentTimeoutError`.
- Verifica post-fix:
  1. Unit test che verifica il timeout corretto per ogni ruolo.
  2. Smoke test: bugHunter inline non viene terminato a 5 minuti.
  3. Build + test suite completa.
- Commit previsto: `fix(subagent): use role-specific timeout instead of hardcoded 300s`
