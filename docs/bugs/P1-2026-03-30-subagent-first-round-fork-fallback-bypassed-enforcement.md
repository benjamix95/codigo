# P1 — Il testo di fallback `fork_context` bypassava l’enforcement del primo round subagent

## Bug Fix Record
- Categoria: A — Critico
- Bug: quando il modello rispondeva nel primo round con testo tipo “fork del contesto non disponibile” senza emettere `tool_call_suggested`, il runtime considerava quel round valido e terminava o continuava male, senza lanciare subagent reali.
- Sintomo: niente card subagent, niente child context visibile, testo utente su limiti `fork`/`fork_context`, poi lavoro svolto con tool normali o sequencing degradato.
- Impatto: rottura del flusso multi-agent reale; regressione di interleaving e progress UI; perdita dell’uso canonico di `subagent_*`; comportamento incoerente anche se i guardrail esistenti restano verdi.
- Gravità: P1
- Steps to reproduce:
  1. Avviare un task con `subagentProviderFactory` attiva e `subagent_*` esposto.
  2. Fare emettere al modello, nel primo round, solo testo del tipo “i subagenti con fork del contesto…”.
  3. Verificare che non arrivino `tool_call_suggested` per `subagent_*`.
  4. Osservare l’assenza di card subagent e il degrado del flusso.
- Risultato attuale: il testo di fallback veniva trattato come completion/round valido; `subagent_first_required` non scattava perché non c’era alcun `tool_call_suggested`.
- Risultato atteso: quel testo deve essere considerato rumore di fallback; il runtime deve continuare automaticamente, correggere il prompt e forzare il passaggio successivo ai tool `subagent_*`.
- Causa probabile:
  - enforcement del primo round agganciato solo a `tool_call_suggested`;
  - nessun riconoscimento dedicato del testo “fork/fork_context non disponibile”;
  - prompt transport-side ancora troppo permissivi verso collaboration/fork nativi.
- Scope consentito:
  - loop `ToolEnabledLLMProvider`
  - helper di introspection/follow-up prompt
  - prompt transport-side Codex/Claude
  - regression tests mirati
- Non-scope:
  - reducer/card UI già corretto nel fix precedente
  - parser MCP startup
  - renderer timeline
- Moduli confinanti da verificare:
  - `ToolEnabledLLMProvider+Send.swift`
  - `ToolEnabledLLMProvider+SendRoundProcessing.swift`
  - `ToolEnabledLLMProvider+ToolIntrospection.swift`
  - prompt Codex/Claude lato Rust
- Test da aggiungere o aggiornare:
  - test end-to-end: testo `fork_context` nel primo round non deve comparire come output finale e deve lanciare almeno un subagent reale
  - test prompt/policy per evitare fork provider-native come prima scelta
  - smoke suite larga Codex/MCP/interleaving dopo il fix
- Strategia di fix minimo:
  - rilevare il testo di fallback `fork_context` nel primo round;
  - non mostrarlo al user e non trattarlo come completion significativa;
  - forzare auto-continuation con prompt correttivo verso `subagent_*`;
  - riallineare i prompt transport-side per evitare il path collaboration/fork come default.
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet` verde
  - `xcodebuild test ...` verde sui guardrail subagent nuovi e sulla suite larga Codex/MCP/interleaving
- Commit previsto:
  - `fix(subagents): recover from fork fallback and enforce native tools`
