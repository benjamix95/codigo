# 2026-03-21 providers core contracts relocation

## Summary
- spostati `LLMProvider` e `ProviderRegistry` da `Providers/Core` a `ProviderBackends/Core`
- nessuna modifica di logica; solo riallineamento del perimetro dei contratti condivisi

## Changes
- `Engine/CoderEngine/Sources/ProviderBackends/Core/LLMProvider.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Core/ProviderRegistry.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'Engine/CoderEngine/Sources/Providers/Core/LLMProvider.swift,Engine/CoderEngine/Sources/Providers/Core/ProviderRegistry.swift,Engine/CoderEngine/Sources/ProviderBackends/Core/LLMProvider.swift,Engine/CoderEngine/Sources/ProviderBackends/Core/ProviderRegistry.swift,Solo Code.xcodeproj/project.pbxproj'`
