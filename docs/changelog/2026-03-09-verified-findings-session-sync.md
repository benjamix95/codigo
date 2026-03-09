# 2026-03-09 — VerifiedFindings session sync e projection persistence

## Obiettivo
Trasformare la foundation del `VerifiedFindingsCore` in una sorgente canonica persistita per le sessioni review/bughunter, con projection condivise lette da panel, MCP e chat.

## Modifiche implementate

### Session envelope canonico
- aggiunto `VerifiedFindingsSessionEnvelope`
- la `CodeReviewSessionSnapshot` ora può contenere:
  - snapshot canonica `VerifiedFindings`
  - projection derivata
  - version metadata di schema

### Sync service
- aggiunto `VerifiedFindingsSessionSyncService` spezzato per responsabilità:
  - core sync
  - artifacts building
  - mapping helpers
- il service converte la snapshot review corrente in envelope canonico con:
  - finding `bug/security`
  - evidence con redaction
  - verification reports sintetizzati dal workflow review attuale
  - patch artifacts
  - revalidation reports derivati dallo stato validation/apply
  - run canonica
  - event log e trace log
  - dedup/duplicate linking di base

### Persistenza e ingest
- `persistLiveReviewState` sincronizza sempre l’envelope prima di scrivere la sessione
- `persistReviewSnapshotMutation` sincronizza sempre l’envelope prima di persistere mutazioni snapshot
- il patch workflow review sincronizza l’envelope dopo verify/prepare/apply

### Projection lato app
- `TaskActivityStore` ora mantiene:
  - envelope `VerifiedFindings` per sessione
  - projection `VerifiedFindings` per conversazione
- `CodeReviewPanelStore` espone envelope e projection correnti senza introdurre logica di dominio locale
- `TaskActivityStore` pubblica nei payload delle live cards i contatori canonici:
  - candidate queue
  - verified queue
  - duplicate count
  - stale candidate count

### Surface MCP / read path
- `MCPSharedState.readCodeReviewFindings` include metadati canonici:
  - `domain`
  - `stale_status`
  - `possible_duplicate_of`
  - `merged_into_finding_id`
  - `recurrence_group_id`
- `MCPSharedState.readCodeReviewStatus` espone i contatori projection del core
- `CodeReviewHandler+Findings` mostra domain/stale/dedup nel rendering testuale MCP

### Bridge compat
- il bridge `CodeReviewSessionSnapshot+VerifiedFindingsProjection` ora usa:
  - l’envelope persistito se presente
  - fallback al sync service solo se la sessione legacy non lo contiene ancora

## Test eseguiti
- suite mirata `CoderEngineTests`:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/VerifiedFindingAdmissionPolicyTests \
  -only-testing:CoderEngineTests/FindingIdentityServiceTests \
  -only-testing:CoderEngineTests/CommandDeduplicationServiceTests \
  -only-testing:CoderEngineTests/SensitiveDataRedactionServiceTests \
  -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests \
  -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests
```

- risultato: 8 test eseguiti, 0 failure

## Limiti residui
- il command path non usa ancora una command API canonica completa con `CommandMeta` end-to-end
- l’idempotency e la serializzazione per entity sono modellate ma non ancora innestate nei workflow MCP review/bughunter completi
- manca ancora uno store persistente separato per checkpoint/replay incrementale
- `Main Chat` non genera ancora in autonomia finding canonici su ogni discovery: oggi la surface più forte resta la sessione review/bughunter persistita
- `Security` non è ancora agganciato come dominio end-to-end con gate quantitativo completo

## Prossimo passo consigliato
- innestare `CommandDeduplicationService` e `EntityExecutionCoordinator` nel command path review/bughunter
- promuovere `VerifiedFindings` a command backend per verify/apply/revalidate
- introdurre gate e metriche quantitativi reali per sbloccare il dominio security
