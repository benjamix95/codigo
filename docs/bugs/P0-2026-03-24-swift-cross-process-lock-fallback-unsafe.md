# P0 — Lock timeout fallback perde protezione cross-process

## Bug Fix Record
- Categoria: A - Critico
- Bug: Quando `acquireAdvisoryFileLock` va in timeout (dopo 10 secondi), `withAdvisoryFileLock` esegue il body con il solo `NSRecursiveLock` (intra-processo), perdendo completamente la serializzazione cross-process.
- Sintomo: Sotto alta contention (o quando il lock file è bloccato da un processo morto), le operazioni procedono senza protezione inter-processo. Due processi (Swift app + Rust MCP server) possono scrivere contemporaneamente sullo stesso file JSON.
- Impatto: Corruzione dello stato condiviso (review snapshots, bughunter snapshots, command queues).
- Gravità: P0
- Steps to reproduce:
  1. Far acquisire il lock file dal processo MCP Rust (es. durante una lunga operazione di write).
  2. Dalla Swift app, tentare un'operazione che richiede il lock.
  3. Dopo 10 secondi di timeout, la Swift app procede senza lock cross-process.
  4. Entrambi i processi scrivono contemporaneamente → dati corrotti.
- Risultato attuale: `MCPSharedState+CrossProcessLock.swift:130-134` — caso `.fallback`: body eseguito con solo `NSRecursiveLock.lock()`.
- Risultato atteso: Il fallback non deve procedere con la write se non ha il lock cross-process. Opzioni:
  - Ritornare errore al chiamante.
  - Ritentare con backoff più lungo.
  - Usare atomic write (write-to-temp + rename) come mitigazione.
- Causa probabile: Design deliberato per disponibilità ("meglio procedere che bloccarsi"), ma il trade-off è troppo rischioso per dati critici.
- Scope consentito: `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift` — `withAdvisoryFileLock`, caso `.fallback`.
- Non-scope: Implementazione del Rust MCP server lock, redesign completo del locking.
- Moduli confinanti da verificare: tutti i chiamanti di `withBugHunterFileLock`, `withCodeReviewFileLock`, `withBugHunterAdvisoryLock`.
- Test da aggiungere o aggiornare:
  - Test: simulare timeout lock → verificare che il body NON viene eseguito (o viene eseguito con atomic write).
  - Test: file lock held da altro processo → comportamento graceful.
- Strategia di fix minimo: Cambiare il fallback da "procedi senza lock" a "usa atomic write (write-to-temp + rename) come mitigazione". Questo non elimina completamente la race ma previene la corruzione parziale.
- Verifica post-fix:
  1. Test lock timeout con body che scrive su file → file non corrotto.
  2. Build + test suite.
- Commit previsto: `fix(mcp-shared-state): use atomic write on lock timeout fallback`
