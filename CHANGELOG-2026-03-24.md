# Changelog — SoloCode — 2026-03-24

## Panoramica

Sessione di manutenzione profonda: analisi dell'intero codebase, risoluzione di 17 problemi
identificati (3 P0 critici, 5 P1 alti, 6 P2 medi), refactoring di 31 file oversized,
e deduplicazione di codice tra i provider Anthropic e OpenAI.

---

## P0 — Fix Critici (committati in precedenza)

### P0.1 — ManagedPostgresService: UI freeze al primo avvio
- **Problema:** `bootstrapIfNeeded()` usava `queue.sync {}` su DispatchQueue seriale,
  bloccando il main thread durante `initdb` e `pg_ctl start` (potenzialmente secondi).
- **Fix:** Convertito a esecuzione asincrona per non bloccare la UI.
- **File:** `Engine/CoderEngine/Sources/PersistenceCore/ManagedPostgresService.swift`
- **Commit:** `5e7c9ab19`, `e19c9d039`

### P0.2 — SSE Frame >1MB silenziosamente persi
- **Problema:** Quando un frame SSE superava 1MB, il buffer veniva svuotato con
  `buffer.removeAll(); continue` senza alcun log o evento di errore.
- **Fix:** Aggiunto logging con `NSLog` e emissione di `StreamEvent.raw(type: "sse_frame_overflow")`
  con dettagli su byte persi e limite. Aggiunto meccanismo `skipUntilNewline` per
  non contaminare il frame successivo.
- **File:** `AnthropicAPIProvider+Execution.swift`, `OpenAIAPIProvider+ChatStream.swift`
- **Commit:** `5e7c9ab19`, `e19c9d039`

### P0.3 — flock(LOCK_EX) senza timeout = deadlock potenziale
- **Problema:** `flock(descriptor, LOCK_EX)` era bloccante senza timeout. Se un altro
  processo moriva tenendo il lock, il processo corrente si bloccava indefinitamente.
- **Fix:** Implementato `LOCK_EX | LOCK_NB` con retry loop e timeout configurabile.
  Aggiunto fallback a `NSRecursiveLock` se il file lock non è acquisibile.
- **File:** `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
- **Commit:** `5e7c9ab19`

---

## P1 — Fix Alti

### P1.1 — EventDeliveryManager: task concorrenti illimitati
- **Problema:** Ogni delivery creava un `Task` senza limite globale. Con molti subscriber
  e alta frequenza, si potevano creare centinaia di task concorrenti (memory/CPU spike).
- **Fix:** Aggiunto `maxConcurrentDeliveries` (default: 32) con waiting queue.
  I task in eccesso vengono accodati e avviati quando uno slot si libera tramite
  `drainWaitingQueue()`.
- **File:** `Engine/CoderEngine/Sources/AgentPipeline/EventBus/EventDeliveryManager.swift`
- **Test:** `Tests/CoderEngineTests/EventDeliveryManagerConcurrencyTests.swift`
- **Commit:** `f00eb3a5a`

### P1.2 — PipelineIntegrationService: race condition teardown vs facade cancel
- **Problema:** `cancelCurrentJob` chiamava `completeTeardown` sincronamente, poi
  lanciava `Task { await facade.cancel() }`. La facade poteva emettere eventi dopo
  che la teardown aveva già ripulito `runtimesByConversation`.
- **Fix:** Invertito l'ordine — ora `facade.cancel()` viene eseguito **prima** di
  `completeTeardown`, garantendo che nessun evento venga emesso post-teardown.
- **File:** `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift`
- **Commit:** `f00eb3a5a`

### P1.3 — SSE parser duplicato (~80 LOC)
- **Problema:** Il pattern byte-by-byte buffer → newline detection → "data:" prefix
  stripping → overflow protection era identico tra Anthropic e OpenAI.
- **Fix:** Estratto `SSELineParser` in `ProviderBackends/Shared/` con API pulita:
  `feed(byte) -> LineResult` che restituisce `.buffering`, `.payload(json)`, `.done`,
  o `.overflow(droppedBytes)`.
- **File nuovo:** `Engine/CoderEngine/Sources/ProviderBackends/Shared/SSELineParser.swift`
- **File aggiornati:** `AnthropicAPIProvider+Execution.swift`, `OpenAIAPIProvider+ChatStream.swift`
- **Test:** `Tests/CoderEngineTests/SSELineParserTests.swift`
- **Commit:** `f00eb3a5a`

### P1.4 — Retry logic duplicata (~160 LOC)
- **Problema:** Il loop di retry con circuit breaker, exponential backoff, transport
  error check era copiato identico tra i due provider.
- **Fix:** Estratto `ProviderRetrySupport` enum (namespace) con:
  - `retryableHTTPStatusCodes`
  - `exponentialBackoffSeconds(attempt:initialDelay:maxDelay:)`
  - `retryDelay(attempt:initialDelay:maxDelay:retryAfter:)`
  - `shouldRetryTransportError(for:)`
  - `isRetryableTransportCode(_:)`
  - `normalizeRetryAfter(_:)`
  - `readErrorBody(from:)`
  - `retryAfterSeconds(from:)`
  - `makeSession(timeoutSeconds:)`
  - `sleep(seconds:)`
  Le extension `+Resilience` di entrambi i provider ora delegano a `ProviderRetrySupport`.
- **File nuovo:** `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderRetrySupport.swift`
- **File aggiornati:** `AnthropicAPIProvider+Resilience.swift`, `OpenAIAPIProvider+Resilience.swift`
- **Test:** `Tests/CoderEngineTests/ProviderRetrySupportTests.swift`
- **Commit:** `f00eb3a5a`

### P1.5 — WorkerPool: force unwrap + busy-wait shutdown
- **Problema 1:** `await group.next()!` era un force unwrap che poteva crashare
  se il TaskGroup era vuoto (edge case con cancellation).
- **Problema 2:** `shutdownAndWait` usava un polling loop con `sleep(50ms)` — busy-wait.
- **Fix 1:** Sostituito con `guard let first = await group.next() else { return fallbackResult }`.
- **Fix 2:** Sostituito con `withTaskGroup` che aspetta il primo tra completamento
  dei task e timeout, senza polling.
- **File:** `Engine/CoderEngine/Sources/AgentPipeline/WorkerPool/WorkerPool.swift`
- **Test:** `Tests/CoderEngineTests/WorkerPoolSafetyTests.swift`
- **Commit:** `f00eb3a5a`

---

## Refactoring — Decomposizione file oversized

### Settings (commit `018aba705`)
31 file superavano il limite di 300 righe. Il monolitico `SettingsView` è stato
decomposto in moduli focalizzati:

| File originale | Righe | Decomposto in |
|---------------|-------|--------------|
| `SettingsView+Sections.swift` | 337 | `CLIToolsSettingsSection.swift` + sottogruppi per provider |
| `SettingsView+Persistence.swift` | 194 | `CodexTomlSaver.swift` (51 righe) |
| `SettingsView+Sync.swift` | 232 | `SettingsSyncCoordinator.swift` (189 righe) |
| `SettingsView+Accounts.swift` | 271 | `CLIToolsSettingsSection+Accounts.swift` |
| `SettingsView+Custom.swift` | 92 | `CustomSettingsSection.swift` (191 righe, espanso) |
| `SettingsView+Rules.swift` | 84 | `RulesSettingsSection.swift` (218 righe, espanso) |
| `SettingsView+CodexCustomModel.swift` | 38 | Integrato in `CLIToolsSettingsSection+CodexGroup.swift` |

**Nuovi file creati:**
- `APIKeysSettingsSection.swift`
- `CLIToolsSettingsSection.swift` + `+Accounts`, `+ClaudeGroup`, `+CodexGroup`, `+GeminiKiloGroup`
- `CustomSettingsSection.swift`
- `RulesSettingsSection.swift`
- `SettingsContainers.swift`
- `ProviderFactoryConfig.swift`

### Accounts (commit `42d147430`)
- Estratto `CodexLoginService` da `CodexLoginView` — separazione UI/logica auth
- Estratto `OpenRouterAuthService` da `OpenRouterLoginView`

### Content/UI (commit `e80ef02d4`)
- Estratto `UIPanelCoordinator` da `ContentView` — coordinamento panel in un oggetto dedicato
- Estratto `WindowChromeControls` — controlli window chrome isolati

### ChatView/Timeline (commit `b299e166f`)
- `ChatTurnView` (monolite) decomposto in:
  - `ChatTurnTimelineInterleaver` — merging turni/eventi
  - `ChatTurnTimelineOrdering` — ordinamento cronologico
  - `InlineToolTraceViews` — rendering trace tool

### UsageFooter (commit `e359ff8fa`)
- Estratto `UsageFooterWorktreeState` — gestione stato worktree separata

### Engine Provider (commit `541e0fbd2`)
- Estratto `AnthropicSSEModels` — tipi SSE event tipizzati per Anthropic
- Estratto `OpenAISSEModels` — tipi SSE event tipizzati per OpenAI
- Estratto `ProviderCircuitBreaker` + `ProviderCircuitBreakerRegistry` in `Shared/`

---

## Test aggiunti/aggiornati

### Nuovi test (questa sessione)
| File | Copertura |
|------|-----------|
| `SSELineParserTests.swift` | Parsing, overflow, recovery, multi-payload, reset |
| `ProviderRetrySupportTests.swift` | Backoff, retry-after, transport errors, session, sleep |
| `EventDeliveryManagerConcurrencyTests.swift` | Concurrency limit, delivery, DLQ, metrics, reset |
| `WorkerPoolSafetyTests.swift` | Safe unwrap, shutdown, capacity, cancel, metrics, reset |

### Test precedenti (sessione precedente)
| File | Copertura |
|------|-----------|
| `ProviderCircuitBreakerTests.swift` | Circuit breaker states, transitions, registry |
| `SSEBufferLimitTests.swift` | Buffer overflow protection (inline simulation) |
| `ManagedPostgresBootstrapSafetyTests.swift` | Bootstrap caching, concurrent access, flock |
| `MCPCrossProcessLockSimplifiedTests.swift` | Advisory locks, reentrancy, FD leaks, timeout |
| `AnthropicSSEModelsTests.swift` | SSE event decoding |
| `OpenAISSEModelsTests.swift` | Chat chunk decoding |
| `CoderEngineErrorTests.swift` | Error types and descriptions |
| `CodexLoginServiceTests.swift` | Login service lifecycle |
| `OpenRouterAuthServiceTests.swift` | Auth service lifecycle |
| `UIPanelCoordinatorTests.swift` | Panel state, modes, folder picker |
| `ProviderFactoryConfigFromDefaultsTests.swift` | Config from UserDefaults |
| `SettingsSyncCoordinatorTests.swift` | Bind, sync, nil safety |
| `ChatTurnTimelineInterleaverTests.swift` | Timeline interleaving |
| `ChatTurnTimelineOrderingTests.swift` | Chronological ordering |

---

## Architettura — Struttura file condivisi

```
Engine/CoderEngine/Sources/ProviderBackends/
├── Shared/
│   ├── CLIErrorClassifier.swift
│   ├── ProviderCircuitBreaker.swift        ← P0 (precedente)
│   ├── ProviderCircuitBreakerRegistry.swift ← P0 (precedente)
│   ├── ProviderRetrySupport.swift          ← P1.4 (NUOVO)
│   ├── SSELineParser.swift                 ← P1.3 (NUOVO)
│   ├── RequestDeduplicator.swift
│   └── ProviderToolEventMapper/
├── Anthropic/
│   ├── Core/
│   │   ├── AnthropicAPIProvider+Execution.swift ← aggiornato
│   │   └── AnthropicSSEModels.swift
│   └── AnthropicAPIProvider+Resilience.swift    ← semplificato
└── OpenAI/
    ├── Streaming/
    │   ├── OpenAIAPIProvider+ChatStream.swift    ← aggiornato
    │   └── OpenAISSEModels.swift
    └── Resilience/
        └── OpenAIAPIProvider+Resilience.swift    ← semplificato
```

---

## Commit History (cronologico)

| Hash | Tipo | Messaggio |
|------|------|-----------|
| `018aba705` | refactor | decompose monolithic SettingsView into modular sections |
| `42d147430` | refactor | extract login services from views into dedicated service layers |
| `e80ef02d4` | refactor | extract UIPanelCoordinator and WindowChromeControls from ContentView |
| `b299e166f` | refactor | decompose ChatTurnView into timeline interleaver, ordering, and trace views |
| `e359ff8fa` | refactor | extract UsageFooterWorktreeState and simplify footer sections |
| `541e0fbd2` | refactor | extract SSE models and provider circuit breaker into shared modules |
| `4866b6eb2` | test | add unit tests for refactored modules |
| `276a423b9` | chore | update Xcode project references and schemes for refactored modules |
| `f00eb3a5a` | fix | resolve P1 issues — concurrency limits, race conditions, dedup shared code |
