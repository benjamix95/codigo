# P1 — Cold start MCP Codex e bypass shell wrapper riaprivano il fallback ai tool nativi

## Bug Fix Record
- Categoria: B
- Bug: quando il registry MCP nativo partiva freddo, il prompt del provider tool-enabled dichiarava che non c'erano tool MCP disponibili; in parallelo il guard shell poteva essere bypassato con wrapper come `command rg`.
- Sintomo: nel primo round Codex poteva interpretare il warmup incompleto come permesso implicito a usare `bash` per discovery workspace, oppure aggirare il blocco con `command rg`.
- Impatto: regressione percepita sull'uso dei tool SoloCode/CoderIDE, ricaduta su tool nativi shell proprio nei turni iniziali, incoerenza rispetto alla policy `coderide_* first`.
- Gravita': P1
- Steps to reproduce:
  1. avviare una sessione Codex con registry MCP ancora freddo o discovery lenta
  2. osservare il prompt costruito dal provider tool-enabled
  3. verificare che la sezione MCP possa dichiarare assenza tool
  4. eseguire discovery shell con `command rg --line-number ...`
- Risultato attuale: prompt ambiguo in cold start e guard shell aggirabile tramite wrapper
- Risultato atteso: il cold start non deve mai autorizzare la shell discovery; i wrapper shell devono restare bloccati come `rg` diretto
- Causa probabile: fallback testuale troppo pessimista in `mcpNativeToolsPromptSection` e parser del comando shell che considerava `command` il comando reale invece del tool sottostante
- Scope consentito:
  - `ToolEnabledLLMProvider+MCPPromptSection`
  - `ToolEnabledLLMProvider+Policy`
  - `ToolEnabledLLMProvider+MCPRegistryWarmup`
  - `UnifiedToolRuntime+ShellDiscoveryGuard`
  - test `CoderEngineTests` correlati
- Non-scope:
  - refactor del transport MCP
  - redesign del protocollo prompt/tool
  - modifiche alla timeline chat
- Moduli confinanti da verificare:
  - `ToolEnabledLLMProviderMCPWarmupTests`
  - `UnifiedToolRuntimeTests+RuntimeTools`
  - prompt strict `SystemPrompts`
- Test da aggiungere o aggiornare:
  - fallback MCP cold registry non deve più dichiarare assenza tool
  - shell discovery via wrapper `command rg` deve essere respinta
- Strategia di fix minimo:
  - sostituire il fallback "no MCP tools" con guidance esplicita che vieta la shell discovery e preserva i tool strutturati
  - allargare il parser shell per saltare wrapper come `command`, `builtin`, `exec`, `noglob`, `time`
  - aumentare leggermente il timeout di warmup primario MCP per ridurre i cold start borderline
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolEnabledLLMProviderMCPWarmupTests/testFallbackPromptSectionDoesNotAdvertiseMCPAsUnavailableWhenRegistryIsCold -only-testing:CoderEngineTests/ToolEnabledLLMProviderMCPWarmupTests/testSendPrewarmsCoderideToolsBeforeBuildingPrompt -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testBashRejectsWorkspaceDiscoveryViaCommandWrapper -only-testing:CoderEngineTests/UnifiedToolRuntimeTests/testBashRejectsWorkspaceDiscoveryViaRipgrep`
- Commit previsto: `fix(codex): harden cold-start MCP guidance and shell discovery guard`
