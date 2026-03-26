# ARCH — Lock ordering non documentato

## Analisi architetturale

### Descrizione
Il codebase ha molteplici meccanismi di locking:
- `fileAccessQueue` (DispatchQueue, intra-processo)
- `legacyWarningQueue` (DispatchQueue, intra-processo)
- `codeReviewFallbackLock` (NSRecursiveLock)
- `bugHunterFallbackLock` (NSRecursiveLock)
- Advisory file locks via `flock()` (cross-processo)

### Problema
Non esiste una gerarchia di lock documentata. Il codice attuale non presenta deadlock, ma l'aggiunta di nuovi path che acquisiscono lock in ordine diverso potrebbe introdurne uno facilmente.

### Ordering attuale implicito
1. `NSRecursiveLock` (sempre primo, dentro `withAdvisoryFileLock`)
2. Advisory file lock (`flock()`)
3. `fileAccessQueue` (per todos, indipendente)
4. `legacyWarningQueue` (interno a `fileAccessQueue`)

### Raccomandazione
Documentare esplicitamente la gerarchia di lock in un commento header nel file `MCPSharedState+CrossProcessLock.swift`. Aggiungere assert o runtime check per violazioni dell'ordine.
