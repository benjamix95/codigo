# Changelog — 2026-03-25 — Fix build e test pre-esistenti

## Contesto
Durante l'analisi dei tool MCP, sub-agent e bug hunter, la build e la test suite risultavano rotte da refactor precedenti incompleti. Questi fix sono prerequisiti per poter verificare qualsiasi altra modifica.

## Fix applicati

### 1. Provider Resilience — wrapper `exponentialBackoffSeconds` mancante
- **File**: `OpenAIAPIProvider+Resilience.swift`, `AnthropicAPIProvider+Resilience.swift`
- **Problema**: dopo centralizzazione in `ProviderRetrySupport`, mancava il forwarding di `exponentialBackoffSeconds` su entrambi i provider → build failure
- **Fix**: aggiunto `static func exponentialBackoffSeconds(attempt:initialDelay:maxDelay:)` con forwarding a `ProviderRetrySupport`

### 2. Test — `isRetryableTransportError` → `shouldRetryTransportError(for:)`
- **File**: `OpenAIAPIProviderTests.swift`, `AnthropicAPIProviderTests.swift`
- **Problema**: metodo rinominato nel source ma non nei test → test build failure
- **Fix**: aggiornato nome metodo e aggiunto label `for:` in tutte le chiamate

### 3. Test — `AgentRole.worker` → `.coder`
- **File**: `WorkerPoolSafetyTests.swift`
- **Problema**: enum case `.worker` rimosso da `AgentRole` ma test ancora lo usava
- **Fix**: sostituito `.worker` con `.coder` (semanticamente equivalente)

### 4. Test — `EventDeliveryManagerConcurrencyTests` API desync
- **File**: `EventDeliveryManagerConcurrencyTests.swift`
- **Problema**: helper usavano API vecchie (`DeadLetterQueue(maxSize:)`, `EventBusEvent` senza `jobId`/`idempotencyKey`, `EventSubscription(id:eventType:handler:)`)
- **Fix**: riscritti helper con API attuali (`capacity:`, `jobId:`, `idempotencyKey:`, `filter: EventSubscriptionFilter`)

## Impatto
- Build: da FAILED a SUCCESS
- Test suite: da non-compilabile a compilabile
