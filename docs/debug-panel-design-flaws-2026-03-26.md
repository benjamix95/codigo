# Debug Panel — Falle di Progettazione

**Data:** 2026-03-26  
**Scope:** Debug Panel, DebugStore, DebugProjection, Debug MCP Tools  
**Priorità:** ordinate per gravità (A → C)

---

## Categoria A — Critici

### 1. Doppio buffer eventi pendenti senza sincronizzazione

**File coinvolti:**
- `PipelineIntegrationService.pendingDebugEventsByConversation` — buffer pipeline
- `ChatConversationRuntimeState.pendingDebugEventsByConversation` — buffer UI routing

**Problema:** Due buffer indipendenti accumulano eventi debug per conversazioni non attive (`PipelineIntegrationService.pendingDebugEventsByConversation` vs `ChatConversationRuntimeState.pendingDebugEventsByConversation`).

**Verifica codice (2026-03-26):** Su cambio conversazione, `ChatPanelView+LifecycleModifiers` esegue **in sequenza** `applyPendingDebugEvents(for: newId)` e poi `bindRuntimeDebugProjection(for: newId)` → `registerDebugStore` → `flushPendingDebugEvents`. Quindi **entrambi** i buffer per la conversazione selezionata tendono a essere drenati, non solo uno.

**Rischi residui:** (1) **ordine**: prima snapshot restore, poi pending UI, poi flush pipeline — se gli eventi dovevano applicarsi in altro ordine, lo stato può divergere; (2) **stesso evento su due percorsi** → possibile duplicazione logica se un evento finisce in entrambi i buffer; (3) percorsi che bufferizzano senza passare da questo handshake (test, teardown, bug di routing).

**Impatto:** Incoerenze o perdite in edge case, non necessariamente “sempre solo un buffer scaricato”.

**Fix suggerito:** Unificare in un unico buffer (preferibilmente nel `PipelineIntegrationService`) e una sola API `enqueueDebugEvent(for:)` per eliminare ambiguità d’ordine e doppio instradamento.

---

### 2. DebugStore singleton condiviso tra conversazioni

**File coinvolti:**
- `ChatPanelView.swift` — `@ObservedObject var debugStore: DebugStore` (singolo)
- `ChatPanelView+PartP_DebugRouting.swift` — snapshot/restore manuale
- `DebugStore+Snapshot.swift` — `SessionSnapshot` incompleto

**Problema:** Un singolo `DebugStore` è condiviso tra tutte le conversazioni. Lo stato viene salvato/ripristinato via snapshot/restore al cambio conversazione.

**Sotto-problemi:**
- Race condition: eventi per conv A applicati al DebugStore mentre mostra conv B
- `restore(from:)` assegna ~35 proprietà singolarmente → ~35 notifiche `objectWillChange`
- Snapshot include `runtimeLogs` ma **non** cattura `streamLogs`, `debugFindings`, né stato `logFileMonitor` (handle/source)

**Fix suggerito:** Un `DebugStore` per conversazione, o almeno batch le assegnazioni in `restore()` per ridurre i rebuild SwiftUI.

---

### 3. Log file monitor non @MainActor-safe

**File coinvolti:**
- `DebugStore+LogFileMonitor.swift:91-148`

**Problema (storico):** l’handler del `DispatchSource` girava su coda globale mutando stato UI.

**Correzione codice attuale:** in `DebugStore+LogFileMonitor.swift` il parsing JSON avviene ancora sulla coda del source (`.global(qos: .utility)`), ma le mutazioni passano da `DispatchQueue.main.async` prima di `addRuntimeLog` — il rischio di data race sulla **scrittura** di `runtimeLogs` è fortemente ridotto.

**Rischi residui:** coerenza se altre parti del `DebugStore` venissero toccate da callback non-main; perf/coda: burst di `main.async` molteplici. Valutare `DispatchQueue.main` come coda del source se si vuole una pipeline single-thread end-to-end sul main.

**Fix suggerito (se si vuole chiudere del tutto):** `queue: .main` sul `DispatchSource` oppure `Task { @MainActor in ... }` per parsing+append atomici sul main.

---

## Categoria B — Importanti

### 4. Buffer overflow silenzioso (FIFO senza priorità)

**File:** `PipelineIntegrationService+DebugProjection.swift:70-82`

**Problema:** Superato il limite di 500 eventi, gli eventi più vecchi vengono eliminati silenziosamente. Nessuna notifica all'utente. Eventi critici (transizioni fase, ipotesi) possono essere eliminati.

**Fix suggerito:** Notifica visiva nel debug panel + prioritizzazione (non eliminare eventi di transizione fase).

---

### 5. Sessione zombie: nessun timeout automatico

**File:** `DebugStore+PhaseFlow.swift`

**Problema:** Una sessione debug non ha timeout. Se l'agente smette di emettere eventi, la sessione resta bloccata in una fase intermedia indefinitamente.

**Fix suggerito:** Watchdog timer (es. 5 minuti senza eventi → warning; 15 minuti → auto-resolve con messaggio "session timed out").

---

### 6. Transizioni di fase incomplete / workaround fragili

**File:**
- `DebugStore+PhaseFlow.swift:128-143` — `isValidTransition`
- `DebugProjectionEventConsumer.swift:52-58` — workaround per fasi saltate

**Problema:** La macchina a stati non permette `describing → instrumenting`, `idle → fixing`. Il consumer compensa forzando `startDebugSession()` e remappando fasi. Questo crea inconsistenza tra fase richiesta e fase effettiva.

**Fix suggerito:** Rivedere la macchina a stati per coprire i pattern reali degli agenti, eliminare i workaround nel consumer.

---

### 7. `awaitingDebugClean` senza fallback

**File:**
- `DebugStore+Cleanup.swift`
- `DebugProjectionEventConsumer.swift` — case `.debugResolved`

**Problema:** Se `awaitingDebugClean = true` e l'evento `debugClean` non arriva mai, la sessione resta bloccata. Il summary è in `pendingResolutionAfterClean` ma mai applicato.

**Fix suggerito:** Timeout su `awaitingDebugClean` (es. 60 secondi → forza risoluzione con warning).

---

### 8. Snapshot incompleto — dati persi al cambio conversazione

**File:** `DebugStore+Snapshot.swift`

**Campi mancanti dallo snapshot (verificato su `DebugStore+Snapshot.swift`):**
- `debugFindings` (`DebugReportState`)
- `streamLogs` (`DebugReportState`)
- Stato / posizione monitor file (oltre a quanto ricostruibile da path+session)

**Nota:** `runtimeLogs` è già incluso nello snapshot; la falla è su findings + stream, non su tutti i log runtime.

**Fix suggerito:** Aggiungere `debugFindings` e `streamLogs` a `SessionSnapshot` (e `restore`).

---

### 9. Weak binding senza rilevamento "morto"

**File:** `DebugProjectionEventConsumer.swift:13-20`

**Problema:** `DebugProjectionStoreBinding.store` è `weak`. Se il DebugStore viene deallocato, gli eventi vengono bufferizzati indefinitamente senza cleanup. Nessun meccanismo rileva che il binding è diventato invalido.

**Fix suggerito:** Controllare `store == nil` in `applyOrBufferDebugEvent` e fare unregister automatico del binding morto.

---

## Categoria C — Minori

### 10. Nessuna persistenza cross-session

**Problema:** Tutto lo stato debug vive in memoria. Al crash dell'app, sessioni debug attive vanno perse. Le conversazioni chat sono persistite ma lo stato debug no.

**Fix suggerito:** Persistenza opzionale delle `SessionSnapshot` su disco (almeno per sessioni con findings).

---

## Schema di dipendenze tra le falle

```
Falla 2 (singleton condiviso)
  ├── aggrava Falla 1 (doppio buffer)
  ├── causa diretta Falla 8 (snapshot incompleto)
  └── contribuisce a Falla 9 (weak binding morto)

Falla 5 (no timeout)
  └── aggrava Falla 7 (awaitingDebugClean)

Falla 6 (transizioni incomplete)
  └── causa i workaround in DebugProjectionEventConsumer
```

## Priorità di intervento suggerita

1. **Falla 3** (log monitor / threading) — in codice attuale già mitigato con `main.async`; eventualmente chiudere del tutto con coda `.main` sul source
2. **Falla 2** (singleton) — fix architetturale, elimina falle 8 e 9
3. **Falla 1** (doppio buffer) — unificare, eliminare perdita eventi
4. **Falla 7 + 5** (timeout/watchdog) — prevenire sessioni zombie
5. **Falla 6** (macchina a stati) — eliminare workaround fragili
6. Resto in ordine di opportunità
