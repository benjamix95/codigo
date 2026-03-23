# 2026-03-23 chat agent pipeline subagents and todos

## Summary
- il fallback `agentPipeline` della chat ora conserva identità swarm/subagent per i task pipeline
- i testi dei worker alimentano anche eventi `subagent_text`, così le live cards hanno contenuto aggiornato
- i `todo_write` batch vengono espansi correttamente nel `TodoStore`
- i marker inline `todo_write` nel testo pipeline vengono convertiti in eventi raw riusando il path esistente dei todo

## Changes
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift`
  - aggiunti helper per metadata swarm stabili e parsing inline `todo_write`
  - aggiunte attività sintetiche `agent` e `subagent_text` per i task pipeline
  - i delta del pipeline inoltrano anche `todo_write` inline al `rawEventHandler`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
  - `handleRawTodoWrite` ora espande i batch usando `EventNormalizer.normalizeTodoWrite`
- `Tests/SoloCodeAppTests/ChatStreamFailureHandlingTests.swift`
  - aggiunti test per marker inline `todo_write` e metadata swarm payload

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests -only-testing:SoloCodeAppTests/SwarmLiveReducerTests`
