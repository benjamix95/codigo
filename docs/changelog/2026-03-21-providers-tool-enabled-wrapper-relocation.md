# 2026-03-21 providers tool enabled wrapper relocation

## Summary
- spostato l’intero cluster `ToolEnabledLLMProvider` da `Providers/Core` a `ProviderBackends/Shared/ToolEnabledLLMProvider`
- nessuna modifica di logica di produzione; solo riallineamento del perimetro del wrapper shared sopra i backend provider

## Changes
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/ToolEnabledLLMProvider.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Helpers/*`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Policies/*`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Send/*`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Subagents/*`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Tools/*`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path del cluster spostato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests -only-testing:CoderEngineTests/ProviderToolEventMapperTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files '<cluster ToolEnabledLLMProvider moved files>,Solo Code.xcodeproj/project.pbxproj'`
