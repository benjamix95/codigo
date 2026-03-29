# Changelog - 2026-03-29 - Subagent sections per launch wave

## Modifiche

- l’interleaver della timeline ora genera più sezioni collassabili per i sub-agent completati, invece di un solo blocco globale
- i sub-agent lanciati nella stessa ondata restano dentro la stessa sezione
- i sub-agent lanciati in momenti distinti vengono separati in sezioni diverse
- la logica vive in `ChatTurnTimelineInterleaver+CompletedSubagents.swift` e riusa la stessa UI di `ChatTurnCompletedSubagentsGroupView`

## Test

- aggiornati i test in `ChatTimelineInterleavingSubagentTests.swift`
- validazione eseguita con:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests`

## Note

- nessuna modifica a runtime swarm o persistenza snapshot
- il fix è confinato alla costruzione dei segmenti timeline
