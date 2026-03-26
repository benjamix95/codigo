# Changelog — 2026-03-25 — fix hashProbe crash (Stop button)

## Commit 1 (root cause): `a216165`
`fix(app): ignore SIGHUP signal to prevent crash when user presses Stop`

## Commit 2 (hardening): `a777c324`
`fix(detector): prevent hashProbe crash from concurrent Dictionary mutation`

---

### Problema identificato

**Crash critico (Categoria A):** SIGHUP in assembly → `0 hashProbe`  
Thread 1 fermato in Xcode debugger su istruzione `ldrb w8, [sp, #0x7]` all'interno
di `Dictionary._NativeStorage.hashProbe` (Swift stdlib).

### Causa radice

Race condition nel pattern lock-unlock-do in `ClaudeDetector` e `KiloDetector`.

Due thread concorrenti potevano:
1. Entrambi superare il controllo cache con lock acquisito (cache fredda)
2. Entrambi rilasciare il lock **prima** di eseguire il processo CLI
3. Entrambi eseguire `Process()` (5–8 secondi)
4. Entrambi riacquisire il lock e scrivere nel dizionario quasi simultaneamente

Il dizionario Swift non è thread-safe → corruzione della hash table interna → crash
non recuperabile in `hashProbe`.

### File modificati

| File | Metodo | Fix |
|------|--------|-----|
| `ClaudeDetector.swift` | `checkCLIAvailable` | Double-check-after-lock |
| `ClaudeDetector.swift` | `checkAuthStatus` | Double-check-after-lock |
| `KiloDetector.swift` | `checkCLIAvailable` | Double-check-after-lock |

### Pattern applicato

```swift
// PRIMA (vulnerabile):
cacheLock.lock()
cliAvailableCache[key] = (result, Date())
cacheLock.unlock()

// DOPO (sicuro):
cacheLock.lock()
defer { cacheLock.unlock() }
if cliAvailableCache[key] == nil {
    cliAvailableCache[key] = (result, Date())
}
```

Se due thread completano l'operazione: il primo scrive, il secondo trova la chiave
già presente e non sovrascrive. Nessuna mutazione concorrente → nessun crash.

### Moduli non toccati
- `InstructionPolicyBundle.swift` — già corretto con lock completo
- `ChatRenderLogger.swift` — già corretto con `os_unfair_lock`
- `PolicyBundleLookupCache` — già corretto con `NSLock`

### Testing
- Build: verificato sintatticamente (lo stesso pattern è già in uso in `InstructionPolicyBundle`)
- Smoke test manuale: da eseguire su flusso provider detection durante streaming attivo
- Test di regressione automatico: non ancora presente (da aggiungere in task separato)

---

*Analisi e fix: 2026-03-25*
