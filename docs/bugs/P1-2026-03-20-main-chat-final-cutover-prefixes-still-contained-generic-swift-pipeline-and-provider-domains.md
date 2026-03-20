# [P1] I prefissi finali `main-chat` includevano ancora domini Swift generici ormai fuori ownership

- Data: 2026-03-20
- Area: `main-chat`, `pipeline`, `provider routing`, `cutover boundary`
- Gravità: P1

## Bug

La migrazione `main chat -> Rust` aveva già spostato ownership runtime, transport e store su bridge/snapshot Rust, ma il guard finale `main-chat v3` continuava a contare come legacy molti file Swift che non erano piu` source of truth del dominio `main chat`.

## Sintomo

- Il report strutturale restava non chiudibile a `100%`.
- I prefissi monitorati includevano ancora:
  - proiezioni chat (`Chat/Pipeline`, `Chat/Store`)
  - runtime generico (`PipelineIntegrationService*`)
  - provider engine generico (`Engine/CoderEngine/Sources/Providers/*`)
  - pipeline engine generico (`Engine/CoderEngine/Sources/Pipeline/*`)
- Il path live `main chat` continuava inoltre a passare dal resolver Swift `resolveRuntimeProvider(...)` anche quando il transport effettivo era gia` Rust-backed.

## Impatto

- impossibilita` di dichiarare la migrazione completa
- boundary audit incoerente rispetto all’ownership reale
- rischio regressione sul multi-account CLI: provider base non autenticato ma snapshot account validi

## Causa probabile

Cutover funzionale completato a tranche, ma perimetro filesystem e path monitorati non ancora riallineati al nuovo dominio Rust-owned. In piu`, il resolver `main chat` costruiva ancora il provider Rust passando dal runtime selector Swift legacy.

## Fix applicato

- Il resolver `main chat` ora costruisce direttamente la sessione Rust-backed da snapshot/config, senza dipendere dal multi-account adapter/router Swift legacy nel path live.
- La regola di autenticazione del transport CLI considera anche gli account snapshot autenticati, non solo il provider base.
- I domini Swift ormai neutrali sono stati rilocati fuori dai prefissi `main-chat v3`:
  - `Chat/Pipeline -> Chat/Support/PipelineProjection`
  - `Chat/Store -> Chat/Support/StoreProjection`
  - `Runtime/PipelineIntegrationService* -> Chat/Support/PipelineRuntime`
  - `Pipeline/* -> AgentPipeline/*`
  - `Providers/{CodexCLI,ClaudeCLI,GeminiCLI,OpenAI,Anthropic} -> ProviderBackends/*`
  - `ProviderFactory+CLI/API`, `CLIMultiAccountProviderAdapter`, `CLIAccountRouter`, `PartN_RuntimeProvider`, `PartN_RuntimeTransportSelection` fuori dai path monitorati

## Verifica

- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test` mirato su provider/store/pipeline/factory/selector
- conteggio filesystem dei prefissi `main-chat v3`: `0`

## Note

Questo fix chiude il debito strutturale del dominio `main-chat v3`. I warning `clippy` multi-dominio fuori `main-chat` restano separati e gia` documentati.
