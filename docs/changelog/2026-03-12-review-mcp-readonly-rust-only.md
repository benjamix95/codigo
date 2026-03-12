# 2026-03-12 — Review MCP read-only rust-only

## Scope
- tool MCP read-only di review/security/bughunter gia' supportati dal core Rust
- rimozione dei fallback host-side Swift

## Modifiche
- reso obbligatorio il bridge Rust per `review_status`, `review_findings`, `review_list_sessions`, `review_get_outcome`
- reso obbligatorio il bridge Rust per `security_status`, `security_findings`
- reso obbligatorio il bridge Rust per `bughunter_status`, `bughunter_findings`, `bughunter_run_history`, `bughunter_explain_cluster`
- eliminata la logica read-only Swift duplicata negli handler MCP

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`
- `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`

## Note
- il build Swift passa; l'esecuzione dei bundle test resta bloccata nell'ambiente corrente dal loader/codesign dei bundle `xctest`
