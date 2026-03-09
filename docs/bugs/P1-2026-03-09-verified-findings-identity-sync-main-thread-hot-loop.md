# P1 — Verified findings sync ricostruiva envelope e deduplica costosa sul main thread

## Bug Fix Record
- Categoria: A
- Bug: l’ingestione di `CodeReviewSessionSnapshot` senza `verifiedFindings` embedded ricostruiva envelope e projection sul main thread, rieseguendo la deduplica identity CPU-heavy e, nello stesso passaggio, ripeteva il rebuild per il payload attività.
- Sintomo: Solo Code poteva bloccarsi e salire a CPU molto alta durante update review/main chat; il sample del processo mostrava il main thread inchiodato su `TaskActivityStore.ingestCodeReviewSnapshot -> VerifiedFindingsSessionSyncService.applyIdentityPolicy -> FindingIdentityService.findDuplicate`.
- Impatto: freeze UI, picchi CPU, ritardo negli aggiornamenti review panel/main chat e rischio di envelope stale quando uno snapshot più nuovo arrivava senza envelope embedded.
- Gravità: alta
- Steps to reproduce:
  1. Avviare una review o ricevere snapshot review incrementali senza `verifiedFindings` embedded.
  2. Accumulare finding/candidate duplicati o quasi duplicati.
  3. Osservare la main chat o il review panel durante l’ingestione dello snapshot.
  4. Eseguire `sample <pid> 5`.
- Risultato attuale: il main thread ricostruisce `VerifiedFindingsResolvedState`, aggiorna la projection e ricalcola anche il payload, con normalizzazioni stringa ripetute e scansioni duplicate.
- Risultato atteso: ogni snapshot deve sincronizzare envelope al massimo una volta per ingest, cacheare il risultato fresco nello snapshot/store e usare una deduplica con chiavi pre-normalizzate e candidate set ridotto.
- Causa probabile: `TaskActivityStore` non riusava il resolved state nello stesso giro di ingestione e `FindingIdentityService` eseguiva confronto O(n²) con `trim/lowercased` ripetuti per ogni coppia candidata.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+CodeReview.swift`
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/FindingIdentityService.swift`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService.swift`
  - test `CoderEngineTests` e `SoloCodeAppTests` collegati
- Non-scope:
  - redesign del panel review
  - refactor dell’intero pipeline verified findings
  - modifiche a persistence PostgreSQL oltre all’uso del risultato sincronizzato corrente
- Moduli confinanti da verificare:
  - `PipelineIntegrationVerifiedFindingsTests`
  - `TaskActivityStoreScopedActivitiesTests`
  - `VerifiedFindingsSessionSyncServiceTests`
  - `FindingIdentityServiceTests`
- Test da aggiungere o aggiornare:
  - regressione su approximate duplicate con line tolerance
  - regressione su caching dell’envelope fresco per mutation sequence successiva
  - smoke sui payload verified findings esistenti
- Strategia di fix minimo:
  - sincronizzare `VerifiedFindingsResolvedState` una sola volta per ingest e riusarlo per cache projection + payload
  - persistire/store lo snapshot già arricchito con envelope fresco
  - sostituire la ricerca duplicate con identità pre-normalizzate e bucket per file/title/summary
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/FindingIdentityServiceTests -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests`
  - security scan scope file: nessun pattern insicuro rilevato
- Commit previsto: `fix(review): remove main-thread verified findings hot loop`

## Evidenza
- Sample salvato in `/Users/benjaminstoica/SoloCode/tmp/process-samples/solo-code-pid-84154-20260309-225045.sample.txt`
- Stack dominante osservata:

```text
ChatPanelView.resolveRuntimeProvider
 -> TaskActivityStore.ingestCodeReviewSnapshot
 -> TaskActivityStore.resolvedVerifiedFindingsState
 -> VerifiedFindingsSessionSyncService.applyIdentityPolicy
 -> FindingIdentityService.findDuplicate
 -> String.lowercased / trimmingCharacters
```

## Fix applicato
- `TaskActivityStore.ingestCodeReviewSnapshot` ora sincronizza lo stato verified una sola volta, arricchisce lo snapshot con l’envelope fresco e riusa lo stesso `verifiedState` per payload e projection cache.
- `resolvedVerifiedFindingsState` non riusa più ciecamente un envelope vecchio come risultato finale quando lo snapshot corrente ne è privo; lo usa solo come base per `existingEnvelope` durante la sync.
- `FindingIdentityService` ora prepara chiavi normalizzate una volta sola, indicizza i finding per fingerprint/file/title/summary e riduce il candidate set prima del calcolo del punteggio.
- `VerifiedFindingsSessionSyncService.applyIdentityPolicy` usa l’indice incrementale invece di riscorrere e ri-normalizzare tutto l’output ad ogni finding.
