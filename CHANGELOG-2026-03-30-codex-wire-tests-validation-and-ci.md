# Changelog — 2026-03-30 — Codex wire tests wired into validation and CI

## Cosa ho cambiato

- Ho collegato la suite `CodexAppServerMCPWireIntegrationTests` al validatore locale `scripts/solocode-validate` quando vengono toccati:
  - `Native/RustCore/src/main_chat/providers/cli/codex_app_server*`
  - parser/config Codex in `Engine/CoderEngine/Sources/Infrastructure/MCP/Config/Parsing/MCPConfigLoader+CodexParsing.swift`
  - provider Codex CLI in `Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/*`
- Ho esteso anche il set di test Codex correlati eseguiti nello stesso ramo:
  - `CodexCLIProviderRealisticSequenceTests`
  - `CodexCLINativeToolInterleavingRegressionTests`
  - `ToolEnabledLLMProviderMCPWarmupTests`
  - `MCPConfigLoaderParsingTests`
  - `CodexCLIProviderInvocationTests`

## CI

- Workflow aggiornato: [.github/workflows/ci.yml](/Users/benjaminstoica/SoloCode/.github/workflows/ci.yml)
- Il job macOS ora:
  - installa Node 20
  - installa `@openai/codex@0.117.0` quando il secret `CODEX_AUTH_JSON` è presente
  - scrive `~/.codex/auth.json` dal secret
  - poi esegue il solito `solocode-validate --trigger ciFull`

## Effetto pratico

- In locale, quando tocchi il boundary Codex/MCP, il validatore non si limita più alle suite generiche: tira dentro anche la suite wire-level reale.
- In CI, se il secret di auth è configurato, la nuova suite wire-level smette di essere solo “best effort” locale e diventa barriera automatica in PR.
- Se il secret non c'è, il resto della CI continua a funzionare e la suite wire-level resta semplicemente non esercitata dal binary reale.
