# P1 — Le card subagent venivano create da eventi `agent` generici, non da subagent reali

## Bug Fix Record
- Categoria: A
- Bug: la UI chat promuoveva qualunque evento `agent` a card swarm/subagent inventando un `swarm_id` sintetico quando il payload non conteneva metadata swarm reali.
- Sintomo: in timeline comparivano card subagent apparentemente attive anche se nessun `subagent_*` era stato davvero eseguito.
- Impatto: falsi positivi gravi nella UX, stato esecutivo fuorviante, pannello swarm non affidabile come fonte di verita'.
- Gravita': P1
- Steps to reproduce:
  1. Ricevere un evento raw `agent` senza `swarm_id` o `group_id` swarm.
  2. Osservare il path `handleRawStreamEventContinuationSideEffects`.
  3. Verificare che la UI generasse un id sintetico `swarm-<provider>-<conversation>` e lo registrasse come card subagent.
- Risultato attuale: un evento `agent` generico poteva apparire come subagent reale.
- Risultato atteso: solo eventi con metadata swarm autentici devono finire nella lane subagent/card.
- Causa probabile: workaround UI introdotto per forzare visibilita' alle card anche in assenza di metadata swarm affidabili.
- Scope consentito:
  - `ChatPanelView+PartP_Streaming2Continuation+SideEffects`
  - test app-side del criterio di proiezione swarm
- Non-scope:
  - refactor completo della pipeline subagent
  - revisione del catalogo tool MCP esportato ai provider
- Moduli confinanti da verificare:
  - `SwarmMetadata`
  - `SwarmLiveReducer`
  - `TaskActivityStore` / lane swarm
- Test da aggiungere o aggiornare:
  - test che blocchi la proiezione swarm per eventi `agent` senza `swarm_id`
  - test che preservi la proiezione per eventi `agent` con metadata swarm validi
- Strategia di fix minimo:
  - fail-closed: niente `swarm_id` sintetici
  - gli eventi `agent` generici restano attivita' normali, non card subagent
- Verifica post-fix:
  - `SoloCodeAppTests/ChatStreamingSwarmProjectionPolicyTests`
- Commit previsto: `fix(chat): stop fabricating swarm cards for generic agent events`
