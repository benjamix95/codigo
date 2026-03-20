# P1 — Main Chat provider transport e CLI routing ancora Swift-owned

## Bug Fix Record
- Categoria: A
- Bug: il path live `main chat` continuava a dipendere da `provider.send(...)` implementato nei provider Swift e dal routing `CLIMultiAccountProviderAdapter` / `CLIAccountRouter`.
- Sintomo: direct stream, plan flow e transport provider della chat non erano ancora owned da Rust; failover multi-account e stream provider restavano fuori dal boundary Rust.
- Impatto: la migrazione `main chat -> Rust only` restava incompleta sul path provider, con rischio regressioni su retry, failover, cancellation e parity degli eventi.
- Gravità: alta
- Steps to reproduce:
  1. aprire la main chat con provider `codex-cli`, `claude-cli`, `gemini-cli`, `openai-api`, `anthropic-api` o `google-api`
  2. seguire il path `sendMessage -> resolveMainChatTransportProvider -> provider.send(...)`
  3. osservare che il transport e il routing account/provider erano ancora Swift-owned
- Risultato attuale: provider transport e multi-account routing non passavano dal core Rust.
- Risultato atteso: la main chat deve usare sessioni provider Rust-backed via bridge FFI, con polling/cancel e normalizzazione eventi dal core Rust.
- Causa probabile: il reducer/runtime della chat erano già migrati, ma il layer provider era rimasto legato al contratto Swift `LLMProvider` e alle implementazioni provider concrete.
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_provider.rs`
  - `Native/RustCore/src/main_chat/providers/*`
  - `Native/RustCore/src/ffi/main_chat.rs`
  - bridge/provider selection Swift della main chat
- Non-scope:
  - code review runtime/providers
  - persistenza finale `ChatStore`
  - provider non-main-chat come `openrouter-api`, `minimax-api`, `grok-api`
- Moduli confinanti da verificare:
  - `ConversationFlowCoordinator`
  - `PipelineIntegrationService`
  - `ProviderFactoryRuntimeParityTests`
  - `CLIMultiAccountProviderAdapterTests`
- Test da aggiungere o aggiornare:
  - test Rust sul lifecycle session provider
  - test Swift sul mapping `MainChatRustTransportProvider`
  - parity test provider/runtime già esistenti
- Strategia di fix minimo:
  - introdurre session FFI Rust per provider
  - instradare il path main chat su un provider Swift minimale che parla solo col bridge Rust
  - preservare il resto del comportamento UI/tool runtime senza refactor laterali
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test` mirato su provider/runtime chat
  - `SOLOCODE_MAIN_CHAT_CUTOVER=1 ./scripts/validate_rust_cutover_boundary.sh ...`
- Commit previsto: `refactor(main-chat): move provider transport sessions into rust`

## Note
- Il path live della chat ora passa dal transport Rust-backed per i provider in scope della tranche.
- Il contratto `LLMProvider` resta nel repo per compatibilità con consumer non-main-chat, ma il transport specifico della chat è stato spostato dietro il bridge Rust.
