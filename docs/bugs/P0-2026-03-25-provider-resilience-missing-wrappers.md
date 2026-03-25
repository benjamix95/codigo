# P0 — Provider Resilience: wrapper mancanti dopo refactor ProviderRetrySupport

## Bug Fix Record
- Categoria: A - Critico
- Bug: dopo il refactor che ha centralizzato le utility di retry in `ProviderRetrySupport`, i wrapper di forwarding in `OpenAIAPIProvider+Resilience` e `AnthropicAPIProvider+Resilience` sono incompleti. Manca `exponentialBackoffSeconds` su entrambi i provider.
- Sintomo: **build failure** — `OpenAIAPIProvider+Execution.swift:56` chiama `Self.exponentialBackoffSeconds(...)` che non esiste su `OpenAIAPIProvider`. Il progetto non compila.
- Impatto: build rotta al 100%, impossibile compilare l'app o eseguire test.
- Gravità: P0 — critico (build bloccata)
- Steps to reproduce:
  1. `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
  2. Osservare errore: `type 'Self' has no member 'exponentialBackoffSeconds'`
- Risultato attuale: build failure con errore di compilazione.
- Risultato atteso: build success — il wrapper deve forwardare a `ProviderRetrySupport.exponentialBackoffSeconds`.
- Causa probabile: refactor incompleto — `retryDelay`, `shouldRetryTransportError`, `sleep`, `makeSession` sono stati wrappati, ma `exponentialBackoffSeconds` è stato dimenticato su entrambi i provider.
- Scope consentito: `OpenAIAPIProvider+Resilience.swift`, `AnthropicAPIProvider+Resilience.swift`
- Non-scope: logica di retry, ProviderRetrySupport, test non correlati
- Moduli confinanti da verificare: `OpenAIAPIProvider+Execution`, `AnthropicAPIProvider+Execution`, tutti i path di retry WebSocket/HTTP
- Test da aggiungere o aggiornare: test esistenti `AnthropicAPIProviderTests` e `OpenAIAPIProviderTests` già coprono backoff.
- Strategia di fix minimo: aggiungere wrapper `static func exponentialBackoffSeconds(attempt:initialDelay:maxDelay:)` su entrambi i provider, con forwarding a `ProviderRetrySupport`.
- Verifica post-fix: build success + test suite CoderEngine pass.
- Commit previsto: `fix(providers): add missing exponentialBackoffSeconds wrappers after ProviderRetrySupport refactor`
