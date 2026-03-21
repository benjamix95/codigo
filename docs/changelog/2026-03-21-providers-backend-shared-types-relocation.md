# 2026-03-21 providers backend shared types relocation

## Summary
- spostati `StreamEvent`, `ModelPricing` e `CLIErrorClassifier` da `Providers` a `ProviderBackends`
- nessuna modifica di logica; solo riallineamento del perimetro infrastrutturale

## Changes
- `Engine/CoderEngine/Sources/ProviderBackends/Core/StreamEvent.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Core/ModelPricing.swift`
- `Engine/CoderEngine/Sources/ProviderBackends/Shared/CLIErrorClassifier.swift`
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i path dei file spostati

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests -only-testing:CoderEngineTests/GeminiCLIProviderStreamParsingTests -only-testing:CoderEngineTests/CodexCLIProviderStreamParsingTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'Engine/CoderEngine/Sources/Providers/Core/StreamEvent.swift,Engine/CoderEngine/Sources/Providers/Core/ModelPricing.swift,Engine/CoderEngine/Sources/Providers/Shared/CLIErrorClassifier.swift,Engine/CoderEngine/Sources/ProviderBackends/Core/StreamEvent.swift,Engine/CoderEngine/Sources/ProviderBackends/Core/ModelPricing.swift,Engine/CoderEngine/Sources/ProviderBackends/Shared/CLIErrorClassifier.swift,Solo Code.xcodeproj/project.pbxproj'`
