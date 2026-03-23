# 2026-03-23 — Debug Pipeline Remediation

## Summary
- Riallineato il contratto `debug_request_user` su `question | reproduce | fix_confirmation`.
- La debug pipeline ora espone uno skeleton esplicito per session start, phase backbone, snapshot, hypothesis, timeline, export e stop.
- `debug_test_check` non usa più SwiftPM: verifica via Xcode sul workspace `Solo Code.xcworkspace`.
- Projection e panel non perdono più eventi buffered in `suspend/suppress` e materializzano gli advanced debug tools come stato typed.
- Il debug panel conserva anche session/workspace log scope e restore dei flag UI principali tra conversazioni.
- Avviata la parity Rust dei debug tools, rimuovendo gli stub statici in favore di implementazioni funzionali.

## Verification
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/Pipeline/Contracts/DebugPipelineContractsTests -only-testing:CoderEngineTests/Pipeline/Contracts/DebugPipelineGateContractsTests -only-testing:CoderEngineTests/Pipeline/Debug/Factory/PipelineDebugJobFactoryTests -only-testing:CoderEngineTests/Pipeline/Debug/Factory/PipelineDebugGateStagesTests -only-testing:CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests/testDebugTestCheckReturnsFailureWhenTestsFail -only-testing:CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests/testDebugSessionStartClearsFailingTestScopeCache -only-testing:CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests/testDebugTestCheckReturnsValidationForNonSwiftProject CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/DebugProjectionEventConsumerGateTests -only-testing:SoloCodeAppTests/PipelineIntegrationDebugProjectionTests -only-testing:SoloCodeAppTests/DebugStoreTests CODE_SIGNING_ALLOWED=NO`
- `cargo test --test server_smoke debug_and_skill_tools_work -- --nocapture` in `Native/CoderideMCPServerRust`

## Notes
- Il worktree era già sporco nell’area debug/UI: sono stati integrati solo gli hunk coerenti con la remediation, lasciando fuori le modifiche locali non correlate.
