# 2026-03-09 — Fix hot loop verified findings su main thread

## Obiettivo
Eliminare il freeze CPU osservato nel sample della main chat/review quando `TaskActivityStore` ricostruisce envelope e projection `VerifiedFindings` da snapshot review privi di envelope embedded.

## Modifiche
- aggiornato `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/FindingIdentityService.swift`
  - introdotte identità pre-normalizzate per `filePath`, `category`, `title`, `summary`
  - aggiunto indice incrementale per fingerprint esatto e bucket `file/title/summary`
  - eliminata la scansione con `compactMap + sorted` e le normalizzazioni ripetute per ogni confronto
- aggiornato `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService.swift`
  - `applyIdentityPolicy` usa un indice identity incrementale durante il fold dei finding ordinati
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
  - `resolvedVerifiedFindingsState` sincronizza dallo snapshot corrente quando l’envelope embedded manca
  - l’eventuale envelope già noto viene passato come `existingEnvelope` per preservare la policy di versioning, non riusato come risultato stale
  - `codeReviewPayload` può ricevere un `verifiedState` già calcolato per evitare rebuild duplicati
- aggiornato `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+CodeReview.swift`
  - durante `ingestCodeReviewSnapshot` lo stato verified viene risolto una sola volta
  - lo snapshot memorizzato/persistito viene arricchito con l’envelope fresco
  - projection cache e payload attività riusano lo stesso risultato sincronizzato
- aggiornato `Tests/CoderEngineTests/VerifiedFindings/FindingIdentityServiceTests.swift`
  - aggiunta copertura su duplicate detection approssimata con line tolerance e summary match
- aggiornato `Tests/SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests.swift`
  - aggiunta regressione che verifica caching dell’envelope fresco sulla mutation successiva

## Validazione eseguita
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/FindingIdentityServiceTests -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests`
  - esito: `TEST SUCCEEDED`
- `audit_security_patterns` sui file toccati
  - esito: nessun pattern insicuro rilevato

## Impatto atteso
- meno lavoro CPU sul main thread durante ingestione snapshot review
- eliminazione del doppio rebuild verified nello stesso ciclo di ingest
- envelope/projection coerenti con l’ultima mutation dello snapshot, anche quando l’envelope non è embedded

## Note
- Durante alcuni test compaiono warning di persistenza MCP su cartelle temporanee assenti; i test targetizzati restano verdi e il fix corrente non espande il perimetro a quel layer.
