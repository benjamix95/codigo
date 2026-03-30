# P1 — Il routing dei subagent privilegiava il fork provider-native invece dei `subagent_*` di SoloCode

## Bug Fix Record
- Categoria: A — Critico
- Bug: dopo il fix sui falsi `completed`, il prompt condiviso del main chat spingeva Codex verso il path provider-native di fork/collaboration anche quando la sessione esponeva già i tool `subagent_*` di SoloCode.
- Sintomo: il modello scriveva messaggi del tipo “I subagenti con fork del contesto non sono partiti per un limite del runtime…”, poi continuava con tool normali senza lanciare davvero i subagent; nessuna card live nel pannello.
- Impatto: regressione del workflow multi-agent reale; perdita di card, trace e contesto child read-only; comportamento peggiore proprio nel runtime dove i `subagent_*` canonici erano disponibili.
- Gravità: P1
- Steps to reproduce:
  1. Avviare una sessione Codex CLI / ToolEnabledLLMProvider con `subagentProviderFactory` attiva.
  2. Chiedere un task che normalmente delega a più subagent.
  3. Osservare il testo assistant e il trace strumenti.
  4. Verificare che il modello provi il path provider-native/fork invece di chiamare `subagent_*`.
- Risultato attuale: il modello poteva tentare il fork provider-native, fallire per limiti runtime, e non aprire nessuna card subagent.
- Risultato atteso: quando la live schema espone `subagent_*`, quei tool devono essere la scelta canonica. Il modello non deve parlare al user di limiti `fork`/`fork_context`; deve fare fallback silenzioso su `subagent_*` o tool diretti.
- Causa probabile:
  - istruzioni condivise troppo aggressive su “provider-native subagent/task capability”;
  - conflitto tra policy forte del `ToolEnabledLLMProvider` e prompt/template più esterni;
  - il provider runtime interpretava il testo “prefer native delegation path” come invito a usare il proprio meccanismo di fork, non i tool `subagent_*` già disponibili.
- Scope consentito:
  - prompt condivisi del main chat
  - template istruzioni profilo Codex
  - regression tests sui testi di policy
- Non-scope:
  - reducer/card UI
  - parser lifecycle subagent
  - MCP server `coderide_subagent_*`
- Moduli confinanti da verificare:
  - `ToolEnabledLLMProvider.toolProtocolPrompt`
  - template `CLIProfileProvisioner`
  - streaming instructions del chat panel
- Test da aggiungere o aggiornare:
  - test che il prompt del `ToolEnabledLLMProvider` privilegi `subagent_*`
  - test che il template Codex scoraggi il path provider-native quando `subagent_*` è esposto
  - smoke sui test esistenti di routing subagent
- Strategia di fix minimo:
  - rendere `subagent_*` il path canonico quando presenti nella live schema;
  - spostare il provider-native path a fallback solo quando `subagent_*` non esiste;
  - vietare esplicitamente testo user-facing su limiti `fork`/`fork_context`;
  - non toccare il fix precedente su lifecycle/card.
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolEnabledLLMProviderSubagentPolicyTests -only-testing:CoderEngineTests/MCPSubagentRoutingTests -only-testing:SoloCodeAppTests/CLIProfileProvisionerInstructionSyncSubagentRoutingTests` verde
- Commit previsto:
  - `fix(subagents): prefer solocode subagent tools over provider fork`
