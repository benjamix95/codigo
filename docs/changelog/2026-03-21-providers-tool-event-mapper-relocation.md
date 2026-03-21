# 2026-03-21 providers tool event mapper relocation

## Summary
- spostato il cluster `ProviderToolEventMapper` da `Providers/Core` a `ProviderBackends/Shared/ProviderToolEventMapper`
- nessuna modifica di logica; solo riallineamento del perimetro dell’infrastruttura di event mapping

## Changes
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Helpers.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapContext.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapIO.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapMCP.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Normalization.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Plan.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Predicates.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Routes.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ProviderToolEventMapperTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+Helpers.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+MapContext.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+MapIO.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+MapMCP.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+Normalization.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+Plan.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+Predicates.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderToolEventMapper/ProviderToolEventMapper+Routes.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Helpers.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapContext.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapIO.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+MapMCP.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Normalization.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Plan.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Predicates.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/ProviderToolEventMapper/ProviderToolEventMapper+Routes.swift,Solo Code.xcodeproj/project.pbxproj'`
