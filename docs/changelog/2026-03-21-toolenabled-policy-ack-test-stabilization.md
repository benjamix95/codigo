# 2026-03-21 toolenabled policy ack test stabilization

## Summary
- stabilizzati i test `ToolEnabledLLMProviderPolicyAck` che non devono dipendere dalla policy globale `AGENTS.md`
- aggiunto `delete_file` al catalogo `fileTools` per allineare il runtime alla policy MCP-only edit

## Changes
- `Tests/CoderEngineTests/ToolEnabledLLMProviderPolicyAck/ToolEnabledLLMProviderPolicyAckTests+PolicyAck.swift`
  - helper `nonPolicyContext(workspace:)`
- `Tests/CoderEngineTests/ToolEnabledLLMProviderPolicyAck/*`
  - i test non-policy usano `skipContextEnrichment: true`
  - diagnostica failure migliorata nei casi MCP/subagent
- `Engine/CoderEngine/Sources/Tools/Catalog/Entries/Core/ToolSchemaCatalog+FileTools.swift`
  - aggiunto `delete_file`

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests -only-testing:CoderEngineTests/ProviderToolEventMapperTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:SoloCodeAppTests/CLIMultiAccountProviderAdapterTests -only-testing:SoloCodeAppTests/RustMainChatProviderAdapterTests`
