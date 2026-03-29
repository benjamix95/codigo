# Changelog - 2026-03-29 - Live subagents anchored sections

## Modifiche

- le live card dei sub-agent non vengono più renderizzate come elementi sciolti nella timeline chat
- ogni wave di sub-agent crea subito una sezione `sub-agents`
- la sezione contiene sia entry `running` sia snapshot terminali
- la sezione parte espansa se contiene activity live e si auto-collassa quando tutte le entry del gruppo sono terminali

## Test

- aggiornati i test di interleaving sub-agent
- aggiornati i test di presentazione del gruppo
- validazione eseguita con:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInterleavingSubagentTests -only-testing:SoloCodeAppTests/ChatTurnCompletedSubagentsGroupPresentationTests`
