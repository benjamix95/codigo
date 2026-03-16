# Rust Cutover Audit - 2026-03-16

## Scopo
- Fotografare lo stato reale del cutover Rust del repository.
- Verificare in modo separato il dominio `CodeReview`.
- Usare un comando ripetibile che possa rispondere in modo binario alla domanda: "fuori dalla UI, siamo a zero Swift?".

## Comando strict workspace

```bash
cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
  --workspace /Users/benjaminstoica/SoloCode \
  --allowlist Config/validation/rust-cutover-swift-allowlist.txt \
  --fail-on-legacy-non-ui \
  --format text
```

Risultato osservato il 2026-03-16:
- exit code `2`
- `1610` file Swift scansionati
- `113` file allowlisted UI/bootstrap
- `1497` file Swift legacy non-UI

## Comando strict review scope

```bash
cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
  --workspace /Users/benjaminstoica/SoloCode \
  --allowlist Config/validation/rust-cutover-swift-allowlist.txt \
  --candidate-files "$(find App/SoloCodeApp/Sources/Panels/CodeReview App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview Engine/CoderEngine/Sources/CodeReview Engine/CoderEngine/Sources/VerifiedFindingsCore Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview -type f -name '*.swift' | sed 's#^./##' | paste -sd, -)" \
  --enforce-legacy-zero-prefixes App/SoloCodeApp/Sources/Panels/CodeReview,App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview,Engine/CoderEngine/Sources/CodeReview,Engine/CoderEngine/Sources/VerifiedFindingsCore,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview \
  --fail-on-legacy-non-ui \
  --format text
```

Risultato osservato il 2026-03-16:
- exit code `2`
- `117` file Swift scansionati
- `45` file allowlisted UI
- `72` file Swift legacy non-UI

## Breakdown review
- `App/SoloCodeApp/Sources/Panels/CodeReview`: `19`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview`: `6`
- `Engine/CoderEngine/Sources/CodeReview`: `29`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `14`
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`: `4`

## Breakdown workspace piu' pesanti
- `Tests/SoloCodeAppTests`: `191`
- `Tests/CoderEngineTests`: `174`
- `App/SoloCodeApp/Sources/Chat`: `141`
- `Engine/CoderEngine/Sources/Providers`: `87`
- `App/SoloCodeApp/Sources/Services`: `71`
- `Engine/CoderEngine/Sources/Tools`: `71`
- `App/SoloCodeApp/Sources/Panels`: `69`
- `Engine/CoderEngine/Sources/Pipeline`: `67`
- `Engine/CoderEngine/Sources/CodebaseIndex`: `64`
- `App/SoloCodeApp/Sources/App`: `59`

## Conclusione
- Il repository non e' ancora 100% Rust fuori dalla UI.
- Il `CodeReview Panel` non e' ancora 100% Rust: il debito residuo e' distribuito fra panel store/coordinator, bootstrap command loop, engine review/session, `VerifiedFindingsCore` e handler MCP.
- La modalita' strict del guard permette ora di trattare questo stato come un'invariante verificabile, non come un'impressione.
