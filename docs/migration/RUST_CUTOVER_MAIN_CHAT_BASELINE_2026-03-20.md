# Main Chat Rust Cutover Baseline - 2026-03-20

## Scopo
- formalizzare il perimetro canonico del dominio `main chat`
- fissare la baseline strutturale usata dal tranche gate
- ordinare il backlog Swift non-UI per priorita' di drenaggio verso Rust

## Prefissi canonici del dominio
- `App/SoloCodeApp/Sources/Chat`
- `App/SoloCodeApp/Sources/Runtime`
- `App/SoloCodeApp/Sources/Accounts`
- `App/SoloCodeApp/Sources/Settings/ProviderFactory/Providers`
- `Engine/CoderEngine/Sources/Pipeline`
- `Engine/CoderEngine/Sources/Providers`

## Comando baseline
```bash
PREFIXES='App/SoloCodeApp/Sources/Chat,App/SoloCodeApp/Sources/Runtime,App/SoloCodeApp/Sources/Accounts,App/SoloCodeApp/Sources/Settings/ProviderFactory/Providers,Engine/CoderEngine/Sources/Pipeline,Engine/CoderEngine/Sources/Providers'
FILES="$(find App/SoloCodeApp/Sources/Chat App/SoloCodeApp/Sources/Runtime App/SoloCodeApp/Sources/Accounts App/SoloCodeApp/Sources/Settings/ProviderFactory/Providers Engine/CoderEngine/Sources/Pipeline Engine/CoderEngine/Sources/Providers -type f -name '*.swift' 2>/dev/null | sed 's#^./##' | paste -sd, -)"

cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
  --workspace /Users/benjaminstoica/SoloCode \
  --allowlist Config/validation/rust-cutover-swift-allowlist.txt \
  --candidate-files "$FILES" \
  --enforce-legacy-zero-prefixes "$PREFIXES" \
  --format json
```

## Risultato osservato
- `240` file Swift scansionati
- `48` file allowlist UI/bootstrap o binding adapter
- `192` file Swift legacy non-UI nel dominio
- `192` file legacy anche nei prefissi enforced del tranche gate

## Breakdown per dominio
- `App/SoloCodeApp/Sources/Chat`: `115`
- `App/SoloCodeApp/Sources/Accounts`: `34`
- `Engine/CoderEngine/Sources/Providers`: `33`
- `App/SoloCodeApp/Sources/Runtime`: `10`
- `App/SoloCodeApp/Sources/Settings/ProviderFactory/Providers`: `0`
- `Engine/CoderEngine/Sources/Pipeline`: `0`

## Priorita' backlog
1. `App/SoloCodeApp/Sources/Chat`
   - dominio piu' grande e piu' vicino al runtime live della `main chat`
   - include ancora stateful logic residua in composer, streaming, prompt/plan flow, task lifecycle e store bridge
2. `App/SoloCodeApp/Sources/Accounts`
   - contiene routing, provisioning e login/identity che impattano il transport/provider runtime
   - e' il secondo collo di bottiglia per il cutover completo del path provider
3. `Engine/CoderEngine/Sources/Providers`
   - resta il centro del debito sul lato provider/tool event mapping e session orchestration generica
   - va drenato senza rompere i consumer non-main-chat
4. `App/SoloCodeApp/Sources/Runtime`
   - contiene ancora coordinatori e projection/debug runtime che possono reintrodurre ownership Swift del flusso

## Hotspot iniziali da drenare
- `App/SoloCodeApp/Sources/Runtime/WorkspaceStore.swift` (`312` righe)
- `App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift` (`291` righe)
- `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift` (`271` righe)
- `Engine/CoderEngine/Sources/Providers/Core/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+SendHelpers.swift` (`312` righe)
- `Engine/CoderEngine/Sources/Providers/Core/ToolEnabledLLMProvider/Policies/ToolEnabledLLMProvider+Policy.swift` (`303` righe)
- `Engine/CoderEngine/Sources/Providers/Core/ToolEnabledLLMProvider/Send/ToolEnabledLLMProvider+SendRoundProcessing.swift` (`279` righe)
- `App/SoloCodeApp/Sources/Chat/Support/StoreProjection/Messages/ChatStoreMarkers.swift` (`308` righe)

## Regola operativa del gate
- quando il diff tocca uno dei prefissi canonici del dominio, il tranche gate si attiva automaticamente
- il baseline di `HEAD` viene trasformato in budget `baseline - 1` per ciascun prefisso toccato
- quindi ogni diff nel dominio `main chat` deve ridurre il backlog Swift non-UI almeno di `1` unita' nel prefisso coinvolto

## Note
- questa baseline e' il freeze iniziale del dominio, non il target finale
- il target finale resta `zero Swift non-UI legacy` nel perimetro `main chat`
- eventuali file UI/bootstrap/binding adapter devono essere giustificati tramite allowlist, non esclusi informalmente
- aggiornamento del 2026-03-20:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/**` e' stato riclassificato come `binding_adapter`
  - `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift` e' stato riclassificato come `binding_adapter` dopo il cutover Rust-only del direct stream
  - `App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift` e' stato riclassificato come `binding_adapter` dopo la rimozione del fallback Swift dal direct stream
  - `App/SoloCodeApp/Sources/Runtime/DebugPipeline/DebugProjectionStoreBinding.swift` e' stato assorbito in `DebugProjectionEventConsumer.swift`, rimuovendo un file Swift residuo dal prefisso `Runtime`
  - il progresso strutturale osservato rispetto al baseline canonico iniziale e' `6/198`, pari a `3.0%`
