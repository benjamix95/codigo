# Bug Fix Record
- Categoria: A — Critico
- Bug: drift contrattuale e perdita di ownership nella debug pipeline
- Sintomo: gate `fix_confirmation` incoerente, verify non aderente al workspace Xcode, projection con event drop, panel senza advanced tool state typed, backend Rust parzialmente stub
- Impatto: verify/cleanup non affidabili, copertura falsa sul path di test reale, panel incoerente tra conversazioni, drift semantico Swift/Rust
- Gravità: P1
- Steps to reproduce:
  1. Avviare una debug pipeline completa che attraversa reproduce, fix, verify e cleanup.
  2. Emissione di `debug_request_user kind=fix_confirmation`, `debug_clean`, `debug_timeline`, `debug_session export`, `debug_resolve`.
  3. Sospendere/riprende la projection o cambiare conversazione durante il flow.
- Risultato attuale: prima della remediation il gate finale poteva fallire per contratto, `debug_test_check` usava solo SwiftPM, gli advanced tool non arrivavano typed al panel, eventi buffered venivano scartati, Rust rispondeva spesso con stub statici.
- Risultato atteso: lifecycle completo enforceato dal DAG, verify Xcode sul workspace reale, projection lossless con replay, panel con stato typed per gli advanced tool, backend Rust osservabilmente coerente con Swift.
- Causa probabile: evoluzione indipendente di policy, factory, runtime Swift, projection UI e wrapper Rust senza test end-to-end di parity.
- Scope consentito: Engine debug pipeline/runtime, App debug projection/store/panel, Tools catalog/handler, Native Rust MCP debug tools, test e docs correlati.
- Non-scope: feature non-debug, flussi review/chat non collegati, file sporchi non coerenti con la remediation.
- Moduli confinanti da verificare: orchestrator retry, EventNormalizer debug path, DebugStore snapshot/restore, runtime log persistence, test harness unified runtime, smoke server Rust.
- Test da aggiungere o aggiornare:
  - DAG/debug contracts
  - `debug_test_check` Xcode path
  - projection replay e resolve-after-clean
  - payload typed per advanced tools
  - snapshot UI completo
  - smoke Rust per debug tools
- Strategia di fix minimo:
  - riallineare il contratto `debug_request_user`
  - introdurre stage espliciti per sessione/fasi/snapshot/hypothesis/timeline/export
  - sostituire verify SwiftPM con verify Xcode
  - rendere lossless buffering e persistence panel/runtime
  - rimpiazzare gli stub Rust con implementazioni funzionali
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/Pipeline/Contracts/DebugPipelineContractsTests -only-testing:CoderEngineTests/Pipeline/Contracts/DebugPipelineGateContractsTests -only-testing:CoderEngineTests/Pipeline/Debug/Factory/PipelineDebugJobFactoryTests -only-testing:CoderEngineTests/Pipeline/Debug/Factory/PipelineDebugGateStagesTests -only-testing:CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests/testDebugTestCheckReturnsFailureWhenTestsFail -only-testing:CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests/testDebugSessionStartClearsFailingTestScopeCache -only-testing:CoderEngineTests/UnifiedToolRuntime/UnifiedToolRuntimeTests/testDebugTestCheckReturnsValidationForNonSwiftProject CODE_SIGNING_ALLOWED=NO`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/DebugProjectionEventConsumerGateTests -only-testing:SoloCodeAppTests/PipelineIntegrationDebugProjectionTests -only-testing:SoloCodeAppTests/DebugStoreTests CODE_SIGNING_ALLOWED=NO`
  - `cargo test --test server_smoke debug_and_skill_tools_work -- --nocapture` in `Native/CoderideMCPServerRust`
- Commit previsto:
  - `fix(debug-contracts): align request kinds and lifecycle stages`
  - `fix(debug-verify): route test_check through Solo Code Xcode targets`
  - `fix(debug-projection): preserve events and workspace-scoped state`
  - `fix(debug-rust): bring debug tools to Swift parity`
