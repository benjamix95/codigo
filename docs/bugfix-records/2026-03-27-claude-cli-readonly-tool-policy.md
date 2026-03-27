# Bug Fix Record — 2026-03-27 — Claude CLI bypass della policy read-only con `preferCoderideMCP`

- Categoria: A — Sicurezza / isolamento runtime
- Bug: quando `preferCoderideMCP` era `true`, `ProviderFactory.claudeTools(...)` filtrava solo i tool overlap con CoderIDE MCP e usciva subito, saltando del tutto il controllo `toolPolicy.allowMutatingTools`.
- Sintomo: in sessioni dichiarate read-only, `ClaudeCLIProvider` poteva ancora ricevere `--allowedTools` contenente tool mutanti come `Bash`.
- Impatto: alto; i path read-only di review analysis e runtime provider potevano restare fail-open lato subprocess Claude CLI anche se `ToolEnabledLLMProvider` host-side era configurato con `allowMutatingTools = false`.
- Gravita': alta

## Steps to reproduce

1. Costruire un provider Claude CLI passando `toolRuntimeReadOnlyPolicy(...)`.
2. Assicurarsi che `config.unifiedToolRuntimeEnabled == true`, quindi `preferCoderideMCP == true`.
3. Configurare `claudeAllowedTools` con un mix di tool overlap CoderIDE e tool mutanti, per esempio `["Read", "Edit", "Bash", "Write", "Search", "Task", "Glob", "Grep"]`.
4. Risolvere il provider tramite `resolveSwarmBackendProvider(...)` in un path review/plan read-only.
5. Osservare la allowlist risultante passata a Claude CLI.

## Risultato attuale pre-fix

Dopo la rimozione degli overlap CoderIDE restavano tool come `Bash` e `Task`; il ramo read-only non veniva mai eseguito, quindi il subprocess Claude CLI continuava a poter invocare tool mutanti dalla sua allowlist interna.

## Risultato atteso

La rimozione degli overlap CoderIDE non deve mai disattivare la policy read-only: se `allowMutatingTools == false`, la allowlist finale deve contenere solo tool read-only supportati, con fallback a `["Read"]` se il filtro svuota la lista.

## Causa radice confermata

- `claudeTools(...)` aveva questa struttura:
  - se `preferCoderideMCP` era `true`, ritornava subito la lista senza overlap;
  - solo negli altri casi valutava `toolPolicy` e il ramo `allowMutatingTools == false`.
- Il problema e' particolarmente rilevante per Claude CLI perche' l'enforcement host-side di `ToolEnabledLLMProvider` non intercetta i tool che la CLI esegue internamente se li ha gia' ricevuti in `--allowedTools`.
- I path read-only realmente esposti al bug sono quelli che passano `toolRuntimeReadOnlyPolicy(...)` a `resolveSwarmBackendProvider(...)`, in particolare:
  - review analysis provider;
  - read-only runtime provider del plan.

## Scope consentito

- `App/SoloCodeApp/Sources/Settings/ProviderFactory/Utility/ProviderFactory+SharedUtilities.swift`
- test dedicati in `Tests/SoloCodeAppTests`
- documentazione di bugfix / changelog correlata

## Non-scope

- redesign dell'intero provider factory;
- modifica della semantica di `ToolEnabledLLMProvider`;
- cambi al catalogo tool Claude CLI non necessari al fix.

## Strategia di fix minimo

- eliminare il `return` anticipato nel ramo `preferCoderideMCP`;
- applicare prima il filtro overlap CoderIDE su una lista intermedia;
- applicare poi la policy read-only sulla stessa lista intermedia;
- aggiungere una regressione specifica per `preferCoderideMCP: true` + `allowMutatingTools: false`.

## Fix applicato

- `ProviderFactory.claudeTools(...)` ora calcola `effectiveTools` una sola volta;
- il `guard` su `toolPolicy` ritorna `effectiveTools` solo quando le mutazioni sono permesse o la policy manca;
- quando `allowMutatingTools == false`, il filtro read-only lavora su `effectiveTools`, quindi `Bash` non sopravvive piu' nel caso MCP-first.

## Test aggiunti o aggiornati

- aggiunto `testClaudeToolsPreferCoderideMCPStillHonorsReadOnlyPolicy` in `Tests/SoloCodeAppTests/ProviderFactoryClaudeAllowedToolsTests.swift`;
- corretto `Tests/SoloCodeAppTests/RustMainChatStoreAdapterScopedApplyTests.swift`, gia' non compilante dopo il refactor a snapshot immutabili, ricostruendo `MainChatStoreConversationSnapshotBridge` e `MainChatStoreSnapshotBridge` invece di mutarne le proprieta' `let`.

## Verifica post-fix

- `ReadLints` pulito sui file toccati;
- `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -only-testing:"SoloCodeAppTests/ProviderFactoryClaudeAllowedToolsTests"`:
  - prima del fix della suite: bloccato da errori di compilazione preesistenti in `RustMainChatStoreAdapterScopedApplyTests.swift`;
  - dopo la correzione del test: build completata e app host lanciata;
  - esito finale non acquisito per hang runtime del runner dopo `CodebaseIndex indexWorkspace: starting full index`.

## Commit previsto

- `fix(provider): honor Claude read-only tools with coderide MCP`
