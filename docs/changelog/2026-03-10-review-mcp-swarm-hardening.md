# 2026-03-10 — Hardening review panel, swarm finalization e MCP teardown

## Modifiche
- `MCPTransportResources` è ora ownership condivisa e idempotente, con chiusura sicura anche su copie di `MCPServerSession`
- `resetSession`, `restartServer`, `session(for:)`, `shutdownAll` ed `evictIdleSessions` rimuovono la sessione dal registry prima del teardown asincrono
- `finalizedSwarmCardSnapshotForTaskCompletion(...)` congela gli `swarmId` del turno chiuso e finalizza solo quelli dopo il flush differito
- il review panel ignora `assistant_update` di tipo `Response` arrivati dopo `finishPanelActionOutput(...)`
- `finalizeResponseMessage(...)` rimuove sempre il binding della response bubble al termine della finalize
- il summary review usa lo stesso `VerifiedFindingsResolvedState` sia per le queue sia per `securityGate`

## Test
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/ReviewPanelChatMessageFactoryTests`
- esito: `TEST SUCCEEDED`
- note:
  - alcune suite `MCPSessionManagerTests` fanno skip dei casi che richiedono il binario `.build/coderide-mcp-server`, comportamento già previsto dai test

## Rischio controllato
- nessun refactor architetturale fuori scope
- nessun cambio al protocollo provider-side degli eventi review
- nessuna modifica alla policy `waitForExit`
