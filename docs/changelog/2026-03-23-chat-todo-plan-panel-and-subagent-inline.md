# 2026-03-23 — Chat todo, plan panel e subagent inline

## Modifiche
- Rimossa la richiesta locale di `plan_create` come prerequisito generale all’esecuzione.
- Limitato il gating del todo alla vera esecuzione/mutazione, lasciando liberi discovery, `skill`, subagent e attivazione plan/debug.
- Esclusi anche i tool `coderide_audit_*` dal gating del todo, perché sono audit non mutativi e non devono bloccare la discovery.
- Separato `plan mode` da `plan panel`: il toggle non apre più il panel automaticamente.
- Estesa la policy di auto-open del panel con `proposalReady`, mantenendo `awaitingClarification` e `awaitingChoice`.
- Reso più prudente l’aggancio del todo card al turno assistant: ora richiede contenuto assistant visibile.
- Integrato `InlineActivityFeedView` nel turno chat live per mostrare attività una per una durante lo streaming.
- Collegate le card subagent live/snapshot al rendering del turno chat.
- Aggiunto transcript persistibile opzionale alle snapshot dei subagent, con bridge Swift/Rust retrocompatibile.
- Aggiornate le card subagent per mostrare transcript live/snapshot e un’azione esplicita di apertura pannello.

## Verifiche
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests -only-testing:SoloCodeAppTests/SwarmLiveReducerTests`
- Esito: successo, 111 test eseguiti senza failure.
