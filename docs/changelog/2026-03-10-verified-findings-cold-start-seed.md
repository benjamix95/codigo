# 2026-03-10 — Verified findings sync seeded from persisted envelope

## Modifiche
- `TaskActivityStore.verifiedFindingsEnvelope(...)` recupera ora anche envelope persistiti o rebuild checkpoint quando cache e snapshot locali sono vuoti
- il primo `ingestCodeReviewSnapshot(...)` dopo un cold start preserva metadata già persistiti invece di rigenerare tutto da zero
- aggiunta regressione che verifica la preservazione del `commandLog` persistito

## Test
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests/testIngestSeedsPersistedEnvelopeOnColdStart`
- esito: `TEST SUCCEEDED`

## Rischio controllato
- nessun cambio a `VerifiedFindingsSessionSyncService`
- nessuna modifica al payload review o alla UI dei finding
