# P1 - 2026-03-08 - Review chat skill execution blocca orchestrator e subagent

## Bug Fix Record
- Categoria: Aree fragili, orchestrazione/runtime tool, async stream
- Bug: la chat di code review può restare bloccata quando invoca `coderide_skill`
- Sintomo: nel pannello activity si vede `mcp_tool_call: coderide/coderide_skill`, ma non arrivano più eventi terminali; subagent e orchestrator restano apparentemente fermi
- Impatto: la review chat non prosegue, i task non si chiudono, e la UX sembra congelata proprio nei flussi di audit/review
- Gravità: P1
- Steps to reproduce:
  1. Aprire la chat del pannello code review
  2. Indurre il modello a chiamare `coderide_skill` o il tool nativo `skill`
  3. Usare una skill che a sua volta prova a orchestrare altri tool/subagent o produce uno stream molto lungo
- Risultato attuale: la chiamata resta in attesa sincrona senza timeout efficace e la chat non riceve una chiusura coerente del task
- Risultato atteso: la skill deve avere vincoli espliciti contro orchestrazione annidata e un timeout hard sia sul path runtime sia sul path provider/subagent
- Causa probabile:
  - il path runtime di `UnifiedToolRuntime+SkillExecution` lanciava `codex exec --json` e aspettava senza limite temporale
  - il path provider di `ToolEnabledLLMProvider+SkillExecution` drenava lo stream del subagent senza timeout proprio
  - il prompt skill non impediva in modo esplicito nuove chiamate a `skill`, `subagent_*` o tool di orchestrazione
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/Async`
  - `Engine/CoderEngine/Sources/Skills`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Skill`
  - `Engine/CoderEngine/Sources/Providers/Core/ToolEnabledLLMProvider/Subagents`
  - test `CoderEngineTests` collegati
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - UI della chat
  - tab Findings / Timeline
  - routing MCP dei tool review già corretto in fix precedenti
- Moduli confinanti da verificare:
  - `InstructionPolicyBundle.skillContent`
  - runtime tool execution
  - provider subagent streaming
  - target `CoderEngineTests`
- Test da aggiungere o aggiornare:
  - test unitario sul timeout asincrono
  - test unitario sul prompt/policy della skill
  - test di regressione sul provider skill che fallisce velocemente quando il subagent non chiude lo stream
- Strategia di fix minimo:
  - estrarre il timeout in un modulo riusabile
  - estrarre policy/prompt skill in un modulo dedicato con timeout override via env per i test
  - riusare la stessa policy sia nel runtime tool sia nel provider/subagent
  - applicare un timeout hard a entrambi i path
- Verifica post-fix:
  - `AsyncTimeoutTests` verde
  - `SkillExecutionPolicyTests` verde
  - `ToolEnabledLLMProviderPolicyAckTests/testExecuteSkillToolFailsFastWhenSubagentStreamStalls` verde
  - nella run più ampia è emerso anche un failure preesistente in `InstructionPolicyBundleTests`, fuori scope di questa fix
- Commit previsto: `fix(review-chat): bound skill execution and isolate orchestration guardrails`

## Note
- Il timeout di default resta `20s`.
- Per test e diagnosi è supportato `CODEX_SKILL_TIMEOUT_SECONDS` con valore intero positivo.

## Aggiornamento 2026-03-08 21:00 CET
- Hardening follow-up confinato al solo path `ToolEnabledLLMProvider+SkillExecution`: gli eventi live inoltrati da skill/subagent ora ripopolano `tool_call_id` e `conversation_id` quando mancanti nel payload originale.
- Gli eventi lifecycle locali `started`, `completed` e `failed` ora espongono in modo coerente `conversation_id` e `subagent_stage`, senza inserire valori opzionali in payload `[String: String]`.
- Regressione coperta in `ToolEnabledLLMProviderPolicyAckTests+SkillExecution.swift` con uno scenario che verifica:
  - fallback di `tool_call_id` e `conversation_id` sugli eventi raw inoltrati
  - riscrittura dell'identità `swarm_id` / `group_id` sul wrapper skill
  - presenza di `conversation_id` e `subagent_stage` sugli eventi lifecycle `started` e `completed`
- Verifica eseguibile:
  - `xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:'CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests/testExecuteSkillToolFailsFastWhenSubagentStreamStalls' -only-testing:'CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests/testExecuteSkillToolPreservesLiveEventScopeWhileRewritingSkillSwarmIdentity'`
  - build del modulo fixata, ma esecuzione finale bloccata da errori app fuori scope: simboli mancanti `ReviewPanelChatStructuredLogView` e `ReviewPanelChatAutoscroll` nel target `Solo Code`
  - build isolata di `CoderEngineTests` non affidabile nel workspace attuale per un ciclo di build dei package dinamici durante `xcodebuild build -target CoderEngineTests`
