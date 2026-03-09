# 2026-03-09 — VerifiedFindings canonical checkpoint rebuild

## Obiettivo
Rendere il backend shared `VerifiedFindings` più vicino a una source-of-truth reale, persistendo snapshot canonica e checkpoint separati dall'envelope derivato.

## Modifiche
- aggiunta persistenza separata per:
  - canonical snapshot `verified-findings/canonical/<session>.json`
  - checkpoint `verified-findings/checkpoints/<session>.json`
- `writeVerifiedFindingsEnvelope` ora salva anche:
  - snapshot canonica
  - checkpoint schema-aware con conteggi e metadata
- `readVerifiedFindingsEnvelope` ora effettua fallback automatico:
  - envelope diretto se presente
  - rebuild dell'envelope dal canonical snapshot se il file derivato manca
- `deleteVerifiedFindingsEnvelopeUnsafe` ora pulisce envelope, canonical snapshot e checkpoint
- aggiunti test di regressione per:
  - roundtrip envelope
  - rebuild da canonical snapshot
  - roundtrip checkpoint
  - fallback `CodeReviewSessionSnapshot -> VerifiedFindings`

## File toccati
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+VerifiedFindings.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsSharedStateTests.swift`

## Validazione
Eseguita:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/VerifiedFindingsSharedStateTests \
  -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests
```

Esito:
- 6 test eseguiti
- 0 failure

## Note
Questo tranche non cambia la UI. Rinforza solo il backend shared e prepara meglio replay/rebuild senza introdurre una seconda source of truth.
