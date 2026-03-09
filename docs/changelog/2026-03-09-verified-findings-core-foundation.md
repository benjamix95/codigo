# 2026-03-09 — VerifiedFindingsCore foundation

## Obiettivo
Introdurre la prima base concreta del `VerifiedFindingsCore` shared, separata dalla UI e riusabile da panel, review chat e main chat.

## Modifiche implementate

### Core domain
- aggiunti i modelli canonici di dominio sotto `Engine/CoderEngine/Sources/VerifiedFindingsCore/Domain`
- introdotti enum per:
  - dominio `bug | security`
  - status finding canonici
  - severity, stale status, retention, visibility
  - verdict di verification e revalidation
  - failure taxonomy minima
  - strategy e apply status delle patch
- aggiunti i modelli:
  - `VerifiedFinding`
  - `VerifiedEvidence`
  - `VerifiedVerificationReport`
  - `VerifiedPatchArtifact`
  - `VerifiedRevalidationReport`
  - `VerifiedPipelineRun`
  - `VerifiedPipelineEvent`
  - `VerifiedCommandMeta`

### Application layer
- aggiunta `VerifiedFindingAdmissionPolicy` per governare la promozione a `verified`
- aggiunto `FindingIdentityService` per fingerprint e dedup iniziale
- aggiunto `CommandDeduplicationService` per idempotency di base
- aggiunto `EntityExecutionCoordinator` per serializzazione semplice per entity
- aggiunto `SensitiveDataRedactionService` per masking base di secret comuni
- aggiunto `VerifiedFindingsCanonicalStore` come store canonico minimale per run, finding, evidence, report, patch, revalidation, command log, event log e trace log

### Projection layer
- aggiunti i modelli di projection per queue candidate/verified e trace snippets
- aggiunto `VerifiedFindingsProjectionBuilder` per costruire projection read-only dal canonical store

### Bridge con l'infrastruttura attuale
- aggiunto un adapter read-only da `CodeReviewSessionSnapshot` al nuovo `VerifiedFindingsCanonicalSnapshot`
- aggiunta una projection derivata `verifiedFindingsProjection` sulla snapshot review esistente
- questo permette di usare il nuovo core come base di lettura senza spostare ancora il panel su una nuova store mutabile

### Progetto e test
- aggiunti i nuovi sorgenti e test al file `Solo Code.xcodeproj`
- aggiunti test mirati per:
  - admission policy
  - identity/dedup
  - idempotency base
  - secret redaction
  - projection builder

## Validazione eseguita
- build del progetto con inclusione dei nuovi file nel target engine
- test eseguiti via:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/VerifiedFindingAdmissionPolicyTests \
  -only-testing:CoderEngineTests/FindingIdentityServiceTests \
  -only-testing:CoderEngineTests/CommandDeduplicationServiceTests \
  -only-testing:CoderEngineTests/SensitiveDataRedactionServiceTests \
  -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests
```

- risultato: 6 test eseguiti, 0 failure

## Limiti consapevoli di questo tranche
- il panel non è ancora migrato per usare il core come command backend
- BugHunter non è ancora stato spostato sul canonical store
- non sono ancora stati implementati replay/checkpoint persistenti
- la failure taxonomy è modellata ma non ancora propagata lungo tutto il workflow review/bughunter esistente
- manca ancora l'integrazione cross-entrypoint completa con main chat e review chat come command client diretti

## Prossimo passo consigliato
- collegare `BugHunter` al `VerifiedFindingsCanonicalStore`
- spostare verify/prepare/apply/revalidate dietro un service condiviso
- aggiungere projection store persistente e rebuild
