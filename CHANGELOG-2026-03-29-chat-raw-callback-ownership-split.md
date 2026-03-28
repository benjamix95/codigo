# Changelog

## 2026-03-29

### Fix
- introdotta una policy esplicita di ownership dei raw callback in `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Policy/MainChatRawCallbackOwnershipPolicy.swift`
- impedito a `handleRawStreamEventContinuation(...)` di chiamare `splitStreamingMessageForNewTurn(...)` quando `shouldApplyPipelineArtifacts == false`
- impedito a `handleRawStreamEventContinuationSideEffects(...)` di proiettare `assistant_update` sul main chat body quando il callback raw non possiede gli artifacts pipeline

### Test
- aggiunti test in `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MainChatRawCallbackOwnershipPolicyTests.swift`
- rieseguiti test mirati su ownership policy, lifecycle pipeline, snapshot preference e interleaving timeline

### Evidenze
- nei log dello stesso run comparivano:
  - `560a41bb-3f78-4dc8-8898-bb6a350a9d0b` con `no_pipeline_turn` e soli marker sintetici
  - `f1c7e6cf-91b8-4b6b-8928-6387e48397c6` con timeline pipeline ricca fuori dalla active surface
- il ramo callback raw stava quindi mutando la UI live pur non essendo owner della timeline pipeline
