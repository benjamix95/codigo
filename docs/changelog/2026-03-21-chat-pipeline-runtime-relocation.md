# 2026-03-21 chat pipeline runtime relocation

## Summary
- spostato il cluster `PipelineRuntime` da `Chat/Support` a `Services/ChatPipeline/Runtime`
- spostato `ChatPanelSupport+UIHelpers` da `Chat/Support` a `Services/ChatThread`
- nessuna modifica di logica; solo riallineamento del perimetro del service di integrazione pipeline e degli helper thread/chat support

## Changes
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationServiceModels.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+ChatPipeline.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+DebugProjection.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+Diagnostics.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventMapping.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+ReviewArtifacts.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+VerifiedFindingsReview.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+UIHelpers.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests/testHandleTaskCompletedMarksCanonicalTodoDoneForReviewerAndTestWriter`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationDebugProjectionTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationLifecycleTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime,App/SoloCodeApp/Sources/Chat/Support/ChatPanelSupport+UIHelpers.swift,App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime,App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+UIHelpers.swift,Solo Code.xcodeproj/project.pbxproj'`
