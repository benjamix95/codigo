# P0 — SubagentExecutionLimiter supera maxConcurrent

## Bug Fix Record
- Categoria: A - Critico
- Bug: `SubagentExecutionLimiter` in `SubagentExecutionSupport.swift` ha un bug di counting tra `release()` e `acquire()` che permette a più task del previsto di girare contemporaneamente.
- Sintomo: In condizioni di alta concorrenza, `maxConcurrent + 1` subagent possono essere in esecuzione simultaneamente.
- Impatto: Consumo eccessivo di risorse (CPU, memoria, token LLM), instabilità potenziale.
- Gravità: P0
- Steps to reproduce:
  1. Configurare `maxConcurrent = 3`.
  2. Lanciare 10 subagent contemporaneamente.
  3. In una finestra di tempo precisa durante un `release()`, un quarto task riesce ad acquisire un slot.
- Risultato attuale: Race condition nel flusso:
  ```
  release():
    running -= 1        // 4 → 3
    waiter.resume()     // schedula il waiter, NON esegue sincrono
    return

  // Window: running = 3, waiter non ha ancora incrementato

  acquire() (da nuovo task):
    if running < maxConcurrent  // 3 < 4 → true!
    running += 1                // 3 → 4 ← BOOM, 5 task attivi (4 + waiter)
  ```
  Tra il decremento in `release()` e l'incremento nel waiter risvegliato, un altro `acquire()` può vedere `running < maxConcurrent` e ottenere un extra slot.
- Risultato atteso: Il contatore `running` non deve mai permettere di superare `maxConcurrent`.
- Causa probabile: Il resume della continuation è asincrono — il waiter non esegue `running += 1` immediatamente ma in un turn successivo dell'actor.
- Scope consentito: `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Subagents/SubagentExecutionSupport.swift` — `SubagentExecutionLimiter`.
- Non-scope: logica di scheduling subagent, SwarmWorkerRunner.
- Moduli confinanti da verificare: `ToolEnabledLLMProvider+SubagentExecution.swift` (chiamante principale).
- Test da aggiungere o aggiornare:
  - Test: 100 acquire/release concorrenti → `running` non supera mai `maxConcurrent`.
  - Test stress: burst di 20 acquire con `maxConcurrent = 3`.
- Strategia di fix minimo: NON decrementare `running` in `release()` quando c'è un waiter. Il waiter ereditata lo slot senza transizione:
  ```swift
  func release() {
      if !waiters.isEmpty {
          let next = waiters.removeFirst()
          // running resta invariato — lo slot passa al waiter
          next.resume()
          return
      }
      running = max(0, running - 1)
  }
  ```
  E nel waiter, rimuovere `running += 1` dopo il resume:
  ```swift
  await withCheckedContinuation { continuation in
      waiters.append(continuation)
  }
  // NON incrementare running — lo slot è già contato
  ```
- Verifica post-fix:
  1. Unit test concorrenza con counter assertion.
  2. Build + test suite.
- Commit previsto: `fix(subagent): fix execution limiter overcounting race condition`
