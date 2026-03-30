# P1 — Il launch ack dei sub agent veniva trattato come completamento reale

## Bug Fix Record
- Categoria: A — Critico
- Bug: i sub agent lanciati da Codex potevano apparire immediatamente `completed` anche se il child context non aveva ancora eseguito alcun lavoro reale.
- Sintomo: nel pannello sub agent compariva subito la spunta verde; Codex passava spesso dai `coderide_subagent_*` MCP shims invece che dal lifecycle nativo del provider; le attività del child thread non arrivavano o risultavano monche.
- Impatto: regressione del flusso multi-agent; falsa percezione di completamento; perdita di affidabilità del pannello read-only dei child contexts; possibile ricaduta sui tool built-in o su shims MCP che non rappresentano il lifecycle vero.
- Gravità: P1
- Steps to reproduce:
  1. Usare Codex con un prompt che delega lavoro a sub agent.
  2. Osservare un `coderide_subagent_*` MCP tool che risponde con testo del tipo `OK — subagent ... launched`.
  3. Aprire il pannello sub agent.
  4. Verificare che il card risulti già completato, pur senza reasoning/output/tool trace del child.
- Risultato attuale: il bridge locale convertiva il launch ack MCP in `agent completed`; il reducer UI lo trattava come completamento terminale; Claude/Codex venivano anche istruiti in alcuni punti a usare gli shims MCP al posto del lifecycle nativo.
- Risultato atteso: un launch ack deve restare un ack tecnico, non un terminale; il provider deve preferire il proprio lifecycle nativo di subagent/task; il pannello deve mostrare un contesto child dedicato e read-only con le attività reali quando disponibili.
- Causa probabile:
  - il server MCP locale dei `coderide_subagent_*` restituisce solo un ack di lancio, non il lifecycle del child;
  - il parser Codex app-server e il mapper Swift sintetizzavano un `agent completed` da quel solo ack;
  - i prompt/provider instructions spingevano ancora verso gli shims `coderide_subagent_*` in chat principale;
  - il pannello non esplicitava abbastanza che il child usa un contesto dedicato/read-only.
- Scope consentito:
  - transport Codex app-server
  - parser/mapping eventi Codex CLI
  - reducer/presentazione Swarm
  - prompt/provider templates per routing subagent
  - test Rust/XCTest correlati
- Non-scope:
  - redesign del pannello Swarm
  - refactor generale dei provider
  - modifica del comportamento interno del server MCP oltre all’ack detection
- Moduli confinanti da verificare:
  - `collabToolCall` nativo Codex
  - `task_started` / `task_progress` / `task_notification` nativi Claude
  - transcript builder subagent
  - synthetic event mapping per `mcp_tool_call`
- Test da aggiungere o aggiornare:
  - parser: launch ack non terminale, errore terminale ancora propagato
  - reducer/transcript: launch ack ignorato, completamento reale preservato
  - pannello/context: descriptor read-only per child thread/task nativi
  - template/provider prompt: preferenza per delegation nativa e divieto di usare `coderide_subagent_*` come proxy
- Strategia di fix minimo:
  - rilevare in modo isolato il launch ack dei `coderide_subagent_*`;
  - non emettere `agent completed` sintetici da quell’ack;
  - filtrare l’ack nella transcript UI e mantenerlo al più come dettaglio `launch acknowledged`;
  - istruire Codex e Claude a usare il lifecycle nativo dei sub agent;
  - mostrare nel pannello un descrittore esplicito di contesto child dedicato/read-only.
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet` verde
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' ...` verde su parser Codex, wire tests, reducer/transcript/panel subagent e instruction sync
- Commit previsto:
  - `fix(subagents): prefer native child lifecycle over launch shims`

## Riferimenti
- Anthropic: sub agents con contesto separato e lifecycle proprio
  - https://docs.anthropic.com/en/docs/claude-code/sub-agents
  - https://platform.claude.com/docs/en/agent-sdk/subagents
- OpenAI: Codex come surface per workflow agentici/multi-agent
  - https://openai.com/codex
  - https://openai.com/index/unlocking-the-codex-harness/
