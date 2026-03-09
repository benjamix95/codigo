# 2026-03-09 — BugHunter cluster explanation on canonical findings

## Obiettivo
Allineare anche `bughunter_explain_cluster` al backend shared `VerifiedFindings`, così tutte le letture principali di `BugHunter` usano la stessa source of truth.

## Modifiche
- `BugHunterHandler+Reads` ora usa `VerifiedFindingsService.resolve(sessionId:)` per spiegare il cluster
- il clustering filtra `domain == bug`
- la descrizione usa `title/category/confidence` del canonical snapshot
- aggiunto test di regressione in `BugHunterHandlerTests`

## File toccati
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Reads.swift`
- `Tests/CoderEngineTests/BugHunter/BugHunterHandlerTests.swift`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/BugHunterHandlerTests"]}'
```

Esito:
- 3 test eseguiti
- 0 failure

## Note
Questo tranche è piccolo ma importante: riduce ancora la dipendenza residua di `BugHunter` dal modello review raw.
