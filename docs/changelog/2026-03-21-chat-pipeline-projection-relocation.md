# 2026-03-21 chat pipeline projection relocation

## Summary
- spostato il cluster `PipelineProjection` da `Chat/Support` a `Services/ChatPipeline/Projection`
- spostato `ChatPanelThreadUIState` da `Chat/Support` a `Services/ChatThread`
- nessuna modifica di logica; solo riallineamento del perimetro dell’infrastruttura di projection/reducer e thread UI state

## Changes
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters/*`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core/*`
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelThreadUIState.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/PipelineIntegrationDebugProjectionTests -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/PipelineProjection/Adapters,App/SoloCodeApp/Sources/Chat/Support/PipelineProjection/Core,App/SoloCodeApp/Sources/Chat/Support/ChatPanelThreadUIState.swift,App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Adapters,App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core,App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelThreadUIState.swift,Solo Code.xcodeproj/project.pbxproj'`
