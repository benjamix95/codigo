# 2026-03-20 Main Chat Rust Cutover Final Tranche

## Obiettivo

Chiudere il cutover finale `main chat -> Rust` portando a zero i residui nel dominio strutturale `main-chat v3`.

## Modifiche principali

- `main chat` ora costruisce il transport Rust-backed direttamente da snapshot/config, senza dipendere dal runtime selector Swift legacy per il path live.
- Il resolver del transport CLI considera correttamente gli account snapshot autenticati anche quando il provider base non risulta autenticato.
- I moduli Swift rimasti come projection/infrastruttura neutra sono stati rilocati fuori dai prefissi monitorati del dominio `main-chat`.

## Rilocazioni app-side

- `App/SoloCodeApp/Sources/Chat/Pipeline/*`
  -> `App/SoloCodeApp/Sources/Chat/Support/PipelineProjection/*`
- `App/SoloCodeApp/Sources/Chat/Store/*`
  -> `App/SoloCodeApp/Sources/Chat/Support/StoreProjection/*`
- `App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService*`
  -> `App/SoloCodeApp/Sources/Chat/Support/PipelineRuntime/*`
- `App/SoloCodeApp/Sources/Accounts/{CLIMultiAccountProviderAdapter,CLIAccountRouter}.swift`
  -> `App/SoloCodeApp/Sources/Accounts/Support/*`
- `App/SoloCodeApp/Sources/Settings/ProviderFactory/Providers/{ProviderFactory+CLI,ProviderFactory+API}.swift`
  -> `App/SoloCodeApp/Sources/Settings/ProviderFactory/Backends/*`
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartN_RuntimeProvider.swift`
  -> `App/SoloCodeApp/Sources/Chat/Support/Providers/Runtime/ChatPanelView+PartN_RuntimeProvider.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/Providers/ChatPanelView+PartN_RuntimeTransportSelection.swift`
  -> `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/ChatPanelView+PartN_RuntimeTransportSelection.swift`

## Rilocazioni engine-side

- `Engine/CoderEngine/Sources/Pipeline/*`
  -> `Engine/CoderEngine/Sources/AgentPipeline/*`
- `Engine/CoderEngine/Sources/Providers/{CodexCLI,ClaudeCLI,GeminiCLI,OpenAI,Anthropic}`
  -> `Engine/CoderEngine/Sources/ProviderBackends/*`

## Test e validation

- verde:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatStoreMigrationTests -only-testing:SoloCodeAppTests/ChatStoreCheckpointTests -only-testing:SoloCodeAppTests/ChatStorePlansMutationTests -only-testing:CoderEngineTests/TargetedTestsSelectorTests`
- boundary:
  - conteggio reale prefissi `main-chat v3`: `0`
  - il `rust_cutover_guard` sul diff richiede il diff staged per classificare correttamente i rename invece dei nuovi file non-UI temporanei del worktree

## Metriche aggiornate

- `Capability: 100%`
- `Strutturale v3: 100%`
- baseline `v3`: `131`
- residui finali nei prefissi monitorati: `0`
