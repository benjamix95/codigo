# P0 — Test API desync: isRetryableTransportError rinominato ma test non aggiornati

## Bug Fix Record
- Categoria: A - Critico
- Bug: i test `AnthropicAPIProviderTests` e `OpenAIAPIProviderTests` chiamano `isRetryableTransportError(error)` che è stato rinominato in `shouldRetryTransportError(for: error)` nel source. Inoltre `WorkerPoolSafetyTests` usa `AgentRole.worker` che non esiste più (sostituito da `.coder`). `EventDeliveryManagerConcurrencyTests` usa API completamente cambiate (`DeadLetterQueue(maxSize:)` → `capacity:`, `EventBusEvent` init senza `jobId`/`idempotencyKey`, `EventSubscription` con `eventType:` string invece di `filter:` struct).
- Sintomo: **test build failure** — 4 file di test non compilano. Impossibile eseguire la suite di test.
- Impatto: intera suite CoderEngine non eseguibile, nessuna verifica possibile.
- Gravità: P0 — critico (test pipeline bloccata)
- Steps to reproduce:
  1. `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" -destination 'platform=macOS'`
  2. Errori di compilazione in 4 test file.
- Risultato attuale: test build failure.
- Risultato atteso: tutti i test compilano e passano.
- Causa probabile: refactor delle API source senza aggiornamento corrispondente dei test. Desync accumulata in più sessioni.
- Scope consentito: `AnthropicAPIProviderTests.swift`, `OpenAIAPIProviderTests.swift`, `WorkerPoolSafetyTests.swift`, `EventDeliveryManagerConcurrencyTests.swift`
- Non-scope: logica source dei provider/worker/event system
- Moduli confinanti da verificare: nessuno — fix limitato ai test
- Test da aggiungere o aggiornare: allineamento dei test esistenti alle API correnti.
- Strategia di fix minimo:
  - Rinominare `isRetryableTransportError` → `shouldRetryTransportError(for:)` nei 2 test file provider
  - Sostituire `.worker` → `.coder` in `WorkerPoolSafetyTests`
  - Riscrivere helper di `EventDeliveryManagerConcurrencyTests` per API attuali (`capacity:`, `jobId:`, `idempotencyKey:`, `filter:`)
- Verifica post-fix: test build success + test pass.
- Commit previsto: `fix(tests): align test API calls with current source signatures`
