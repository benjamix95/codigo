# 2026-03-08 - Review chat skill execution fix

## Cosa cambia
- estratto `AsyncTimeout` in `Engine/CoderEngine/Sources/Infrastructure/Async/AsyncTimeout.swift`
- estratta la policy di esecuzione skill in `Engine/CoderEngine/Sources/Skills/SkillExecutionPolicy.swift`
- `UnifiedToolRuntime+SkillExecution` ora usa timeout riusabile e policy centralizzata
- `ToolEnabledLLMProvider+SkillExecution` ora applica lo stesso timeout anche al consumo dello stream del subagent
- aggiunto supporto a `CODEX_SKILL_TIMEOUT_SECONDS` per test e diagnosi locali

## Effetto pratico
- la chat di code review non resta più appesa indefinitamente quando una skill entra in orchestrazione annidata o quando lo stream del subagent non termina
- i fallimenti arrivano come `tool_result` coerente con dettaglio di timeout invece di lasciare il task sospeso
- i vincoli prompt impediscono alle skill di richiamare `skill`, `subagent_*` e altri strumenti di orchestrazione dall’interno

## Test
- aggiunti `Tests/CoderEngineTests/AsyncTimeoutTests.swift`
- aggiunti `Tests/CoderEngineTests/SkillExecutionPolicyTests.swift`
- aggiunto `Tests/CoderEngineTests/ToolEnabledLLMProviderPolicyAck/ToolEnabledLLMProviderPolicyAckTests+SkillExecution.swift`
- verifica eseguita sui test nuovi e specifici della fix; nella run più ampia è emerso un failure già presente in `InstructionPolicyBundleTests`, non introdotto da questa modifica
