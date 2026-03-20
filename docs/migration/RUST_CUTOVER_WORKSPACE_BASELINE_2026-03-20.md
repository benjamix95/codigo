# Rust Cutover Workspace Baseline - 2026-03-20

## Scopo
- fissare la baseline canonica workspace-level del cutover totale a Rust
- distinguere i domini non-UI gia' hard-failable dai domini ancora misti UI/business
- usare una fotografia reale e ripetibile del repository

## Comando strict workspace
```bash
cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
  --workspace /Users/benjaminstoica/SoloCode \
  --allowlist Config/validation/rust-cutover-swift-allowlist.txt \
  --fail-on-legacy-non-ui \
  --format text
```

## Risultato osservato
- `1615` file Swift scansionati
- `305` file allowlist UI/bootstrap o adapter esplicitamente tollerati
- `1310` file Swift legacy non-UI nel workspace

## Domini legacy piu' pesanti
- `Tests/SoloCodeAppTests`: `192`
- `Tests/CoderEngineTests`: `183`
- `App/SoloCodeApp/Sources/Chat`: `115`
- `App/SoloCodeApp/Sources/Panels`: `50`
- `Engine/CoderEngine/Sources/Infrastructure`: `94`
- `App/SoloCodeApp/Sources/Services`: `71`
- `Engine/CoderEngine/Sources/Tools`: `71`
- `Engine/CoderEngine/Sources/AgentPipeline`: `67`
- `App/SoloCodeApp/Sources/App`: `53`
- `Engine/CoderEngine/Sources/CodebaseIndex`: `64`
- `App/SoloCodeApp/Sources/Tasking`: `35`
- `Engine/CoderEngine/Sources/ProviderBackends`: `54`
- `App/SoloCodeApp/Sources/Debug`: `38`
- `App/SoloCodeApp/Sources/Accounts`: `34`
- `App/SoloCodeApp/Sources/Git`: `35`
- `Engine/CoderEngine/Sources/Providers`: `33`

## Domini hard-fail immediati
Questi prefissi entrano subito nel tranche gate totale quando un diff li tocca:
- `App/SoloCodeApp/Sources/Accounts`
- `App/SoloCodeApp/Sources/Context`
- `App/SoloCodeApp/Sources/Debug`
- `App/SoloCodeApp/Sources/Git`
- `App/SoloCodeApp/Sources/Planning`
- `App/SoloCodeApp/Sources/Runtime`
- `App/SoloCodeApp/Sources/CodeReview`
- `App/SoloCodeApp/Sources/Chat`
- `Engine/CoderEngine/Sources/Infrastructure`
- `Engine/CoderEngine/Sources/Tools`
- `Engine/CoderEngine/Sources/AgentPipeline`
- `Engine/CoderEngine/Sources/CodebaseIndex`
- `Engine/CoderEngine/Sources/ProviderBackends`
- `Engine/CoderEngine/Sources/Providers`
- `Engine/CoderEngine/Sources/PersistenceCore`
- `Engine/CoderEngine/Sources/Runtime`
- `Engine/CoderEngine/Sources/Workspace`
- `Engine/CoderEngine/Sources/Validation`
- `Engine/CoderEngine/Sources/Policy`
- `Engine/CoderEngine/Sources/SystemPrompts`
- `Tools/CoderIDEMCPServer/Sources/Runtime`
- `Tools/CoderIDEMCPServer/Sources/Tools`

## Domini da spezzare prima dell'hard-fail totale
- `App/SoloCodeApp/Sources/Panels`
- `App/SoloCodeApp/Sources/App`
- `App/SoloCodeApp/Sources/Services`
- `App/SoloCodeApp/Sources/Tasking`
- `App/SoloCodeApp/Sources/Settings`
- `App/SoloCodeApp/Sources/Editor`
- `App/SoloCodeApp/Sources/Swarm`

## Regola operativa
- se un diff entra in un prefisso hard-fail workspace-level, il backlog di quel prefisso deve scendere di almeno `1`
- nessun nuovo file Swift non-UI e' ammesso
- i domini misti restano temporaneamente fuori dall'hard-fail totale finche' non viene separata meglio la UI dalla business logic
