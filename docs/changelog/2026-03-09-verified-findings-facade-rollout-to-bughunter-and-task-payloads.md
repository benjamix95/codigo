# 2026-03-09 — VerifiedFindings facade rollout to BugHunter and task payloads

## Obiettivo
Propagare il facade `VerifiedFindingsService` anche alle superfici secondarie, così `BugHunter` status e task payload usano davvero lo stesso backend shared già usato da review/security.

## Modifiche
- `BugHunterHandler+Reads` ora mostra:
  - `verified_envelope_source`
  - `verified_replay_candidates`
  - `verified_replay_findings`
- `TaskActivityStore+VerifiedFindings` ora aggiunge al payload:
  - `verified_envelope_source`
  - `verified_replay_candidate_count`
  - `verified_replay_findings_count`
  - `verified_security_gate_ready`
- aggiunti test di regressione in:
  - `BugHunterHandlerTests`
  - `PipelineIntegrationVerifiedFindingsTests`

## File toccati
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Reads.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+VerifiedFindings.swift`
- `Tests/CoderEngineTests/BugHunter/BugHunterHandlerTests.swift`
- `Tests/SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests.swift`

## Validazione
Eseguita con `xcodebuildmcp`:

```bash
xcodebuildmcp macos test --project-path 'Solo Code.xcodeproj' --scheme 'Solo Code-Debug' \
  --json '{"extraArgs":["-only-testing:CoderEngineTests/BugHunterHandlerTests","-only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests"]}'
```

Esito:
- 4 test eseguiti
- 0 failure

## Note
Questo tranche non cambia la pipeline di dominio. Completa la propagazione del facade shared a due entrypoint che prima restavano parzialmente “legacy”.
