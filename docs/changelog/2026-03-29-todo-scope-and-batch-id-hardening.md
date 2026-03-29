# 2026-03-29 — TODO scope and batch id hardening

## Modifiche
- Limitato il fallback ID nel bridge raw TODO in [`PipelineIntegrationService+TodoRawEventSupport.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+TodoRawEventSupport.swift): `payload.taskId` viene riusato solo per eventi con un singolo todo, evitando collisioni nei batch `todos_json`.
- Reso piu' stretto lo scope dei canonical in [`TodoStore+Queries.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Queries.swift): il fallback ai legacy unscoped ora vale solo se non esistono canonical scoped da nessuna parte.
- Aggiunto il regression test batch in [`PipelineIntegrationTodoBatchTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/PipelineIntegrationTodoBatchTests.swift) per bloccare la sovrascrittura di piu' todo sullo stesso ID.
- Aggiunto il regression test scope in [`TodoStoreCanonicalScopeTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/TodoStoreCanonicalScopeTests.swift) per impedire il bleed cross-conversation e preservare il fallback legacy puro.
- Documentati entrambi i bug in `docs/bugs/` e raccolto il perimetro del fix nel bugfix record dedicato.

## Verifiche
- `read_lints` sui file toccati: non disponibile nel workspace corrente (`No recognized linter found. Supported: Swift, Cargo.`)
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationTodoBatchTests -only-testing:SoloCodeAppTests/TodoStoreCanonicalScopeTests -only-testing:SoloCodeAppTests/EventNormalizerTodoTests`
- Esito: successo, 11 test eseguiti senza failure.

## Note
- Il lavoro resta confinato ai due bug logici prioritari emersi dal report.
- I colli di bottiglia prestazionali della chat non sono stati modificati in questo passo.
