# P1 — Patch workflow ancora non stateful nel core Rust

## Sintomo
Il workflow patch review usava `review_core_patch_handle_action` solo per pianificare step e validare queue context, ma la sessione runtime non era posseduta dal core Rust.

## Impatto
- sequencing patch ancora orchestrato lato Swift
- impossibilità di interrogare uno stato runtime canonico del patch flow
- rischio di drift fra planner Rust e executor Swift su step successivi/terminali

## Fix applicato
- introdotti entrypoint Rust stateful:
  - `review_core_patch_start_runtime`
  - `review_core_patch_apply_runtime_result`
  - `review_core_patch_get_runtime_state`
- aggiunto `review_patch/runtime.rs` con session store runtime in Rust
- aggiornato `VerifiedFindingsPatchExecutionService` per guidare l’esecuzione tramite loop runtime Rust
- mantenuto `review_core_patch_handle_action` solo per queue/lifecycle compatibility

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- tentata validazione `xcodebuild test` sulle suite review app/engine

## Nota
Il runner ha un problema ambientale intermittente sul plug-in Xcode `IDESimulatorFoundation/CoreSimulator`, che può interrompere la validazione prima della compilazione. Il codice Rust e la suite cargo risultano verdi.
