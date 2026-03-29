# P1 — Mancava una regressione integrata sul follow-up Codex con MCP freddo

## Bug Fix Record
- Categoria: B
- Bug: il codice era già hardenizzato sui singoli punti, ma mancava una regressione che verificasse l'intero loop `primo round con MCP freddo -> suggestion shell discovery bloccata -> prompt di follow-up coerente -> risposta finale`.
- Sintomo: i test locali coprivano separatamente il fallback prompt cold registry e il blocco shell, ma non l'interazione reale tra i due nel provider tool-enabled multi-round.
- Impatto: possibile reintroduzione silenziosa del problema senza test rosso, soprattutto nei round iniziali Codex.
- Gravita': P1
- Steps to reproduce:
  1. far partire `ToolEnabledLLMProvider` con `MCPNativeToolRegistry` vuoto
  2. nel primo round suggerire `bash` con `command rg`
  3. lasciare che il provider costruisca il prompt di follow-up
  4. verificare che il follow-up non declassi a "no MCP tools" e mantenga guidance strutturata
- Risultato attuale: copertura frammentata
- Risultato atteso: una regression integrata deve fallire appena il follow-up reintroduce messaging ambiguo o perde il dettaglio del blocco shell
- Causa probabile: suite separate su helper e runtime, senza test sul loop completo `send -> validation error -> buildFollowUpPrompt -> second round`
- Scope consentito:
  - test `ToolEnabledLLMProviderPolicyAck`
  - helper di test per catturare i prompt round-by-round
- Non-scope:
  - modifiche ulteriori al runtime di produzione
  - refactor del provider tool-enabled
- Moduli confinanti da verificare:
  - `ToolEnabledLLMProvider+Send`
  - `ToolEnabledLLMProvider+SummariesAndParsing`
  - `ToolEnabledLLMProvider+MCPPromptSection`
  - `UnifiedToolRuntime+ShellDiscoveryGuard`
- Test da aggiungere o aggiornare:
  - round integrato con cold registry, `command rg` bloccato e follow-up prompt verificato
- Strategia di fix minimo:
  - aggiungere un provider di test che catturi i prompt di ciascun round
  - aggiungere una sola regressione sul loop completo
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests/testColdMCPRoundRejectsShellDiscoveryAndFollowUpPromptKeepsStructuredGuidance`
- Commit previsto: `test(codex): cover cold-start MCP follow-up recovery`
