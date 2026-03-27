# 2026-03-27 — Plan mode agent/manual-build unification

## Cosa cambia
- `Plan` pre-build non prende più un route runtime separato: ora usa lo stesso path di `Agent`, scegliendo `standardStream` sui transport Rust e `agentPipeline` sui provider non-Rust.
- Il prompt di planning usa lo stesso contratto tool/subagent di `Agent`, con guard esplicito che blocca tool mutanti e comandi write finché l’utente non preme `Build`.
- Le domande `plan_request_user_input` restano visibili nella timeline chat invece di essere ridotte a uno stato sintetico “answer in panel”.
- Alla pressione di `Build`, il thread riceve solo il messaggio utente `Proceed with the plan.`; il contesto domande viene azzerato e l’esecuzione parte nello stesso thread.

## Dettagli tecnici
- Rimosso il path `planFlow` dalla selezione `MainChatSendExecutionRoute`.
- `sendMessage()` preserva il `planningState` precedente quando il turno è una risposta a chiarimenti, così il prompt viene costruito con il contesto corretto senza bloccare il turn.
- Aggiunto `planBuildGuardViolation(...)` per fail-closed su `mcp_tool_call` mutanti e `command_execution` write durante le fasi pre-build.
- Aggiunto sync post-stream del piano Agent-backed verso `PlanBoard`, `PlanHistoryStore` e attachment del messaggio assistant finale.

## Test
- `SoloCodeAppTests/ClaudeProviderIntegrationTests`
- `SoloCodeAppTests/RustMainChatProviderFactoryTests`
- `SoloCodeAppTests/PlanBuildGuardTests`
