# 2026-03-09 — VerifiedFindings command dedup e serialization

## Obiettivo
Portare i concetti di idempotency e serializzazione per entity dal livello di modello al path di comando review reale.

## Modifiche implementate

### Command coordination
- aggiunto `VerifiedFindingsCommandCoordinator` nel core condiviso
- il coordinator usa:
  - `CommandDeduplicationService`
  - `EntityExecutionCoordinator`
- supporta due esiti:
  - `executed`
  - `deduplicated`

### Integrazione nel command path review
- `applyReviewMutation` usa ora il coordinator per:
  - `apply_fix`
  - `dismiss`
  - `comment`
- `handlePatchWorkflowCommand` usa ora il coordinator per:
  - `verify_finding`
  - `prepare_patch`
  - `verify_patch`
  - `apply_patch`
  - `open_pr`
  - `merge_pr`
  - `resolve_conflicts`

### Metadata condivisa
- introdotto helper `verifiedCommandMeta(...)` per costruire `VerifiedCommandMeta` a partire dal command bus review
- i command vengono deduplicati usando:
  - `command.id`
  - `entityId`
  - `requestFingerprint`

### Persistenza coerente
- anche i path deduplicati o serializzati continuano a usare la snapshot sincronizzata `VerifiedFindings`
- il patch workflow aggiorna MCP shared state, registry e task activity passando sempre dal path canonico sincronizzato

### Refactor di mantenibilità
- spezzati file troppo grandi toccati nel tranche precedente:
  - `TaskActivityStore+VerifiedFindings.swift`
  - `MCPSharedState+CodeReviewReads.swift`
  - split del session sync service in più file

## Test eseguiti
- suite mirata `CoderEngineTests`:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/VerifiedFindingAdmissionPolicyTests \
  -only-testing:CoderEngineTests/FindingIdentityServiceTests \
  -only-testing:CoderEngineTests/CommandDeduplicationServiceTests \
  -only-testing:CoderEngineTests/SensitiveDataRedactionServiceTests \
  -only-testing:CoderEngineTests/VerifiedFindingsProjectionBuilderTests \
  -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests \
  -only-testing:CoderEngineTests/VerifiedFindingsCommandCoordinatorTests
```

- risultato: 9 test eseguiti, 0 failure

## Limiti residui
- il coordinator è integrato sul path review, ma non ancora sul path BugHunter completo end-to-end
- manca ancora l’uso esplicito di `expectedEntityVersion` per conflict checking vero
- il retry governance completa è ancora solo parzialmente modellata, non ancora propagata in tutti i workflow
- `Main Chat` non crea ancora run canoniche autonome su ogni discovery, anche se ora legge meglio le surface condivise tramite sessioni persistite

## Prossimo passo consigliato
- collegare `BugHunter` allo stesso coordinator/command path
- aggiungere version conflict checks reali sui finding canonici
- introdurre run budget, timeout e retry policy esplicite nel command backend
