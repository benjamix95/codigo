# 2026-03-27 — Claude CLI read-only tool policy honored with `preferCoderideMCP`

## Obiettivo

Evitare che i provider Claude CLI usati in contesti read-only continuino a esporre tool mutanti nel flag `--allowedTools` quando il runtime preferisce CoderIDE MCP.

## Cosa cambia

- `ProviderFactory.claudeTools(...)` non fa piu' `return` anticipato quando `preferCoderideMCP` e' `true`;
- il filtro overlap CoderIDE e la policy read-only vengono ora applicati in sequenza sulla stessa lista effettiva di tool;
- nei path read-only di review e plan, tool mutanti come `Bash` non restano piu' disponibili al subprocess Claude CLI solo perche' il runtime e' in modalita' MCP-first.

## Impatto

- le sessioni di code review analysis che passano `toolRuntimeReadOnlyPolicy(...)` non lasciano piu' `Bash` dentro `--allowedTools`;
- i provider runtime read-only costruiti da `resolveSwarmBackendProvider(...)` restano coerenti con `allowMutatingTools = false` anche quando `config.unifiedToolRuntimeEnabled` abilita `preferCoderideMCP`;
- si chiude un fail-open host-side: il guard `ToolEnabledLLMProvider` non era sufficiente, perche' Claude CLI puo' eseguire internamente i tool gia' presenti nella allowlist del proprio subprocess.

## Test e verifica

- aggiunta regressione in `Tests/SoloCodeAppTests/ProviderFactoryClaudeAllowedToolsTests.swift` per il caso `preferCoderideMCP: true` + `allowMutatingTools: false`;
- corretto `Tests/SoloCodeAppTests/RustMainChatStoreAdapterScopedApplyTests.swift`, gia' rotto da un refactor verso snapshot bridge immutabili, per sbloccare la build del target test;
- `ReadLints` pulito sui file toccati;
- `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -only-testing:"SoloCodeAppTests/ProviderFactoryClaudeAllowedToolsTests"` compila e lancia l'app host, ma il run resta appeso durante bootstrap dopo `CodebaseIndex indexWorkspace: starting full index`.

## File toccati

- `App/SoloCodeApp/Sources/Settings/ProviderFactory/Utility/ProviderFactory+SharedUtilities.swift`
- `Tests/SoloCodeAppTests/ProviderFactoryClaudeAllowedToolsTests.swift`
- `Tests/SoloCodeAppTests/RustMainChatStoreAdapterScopedApplyTests.swift`
