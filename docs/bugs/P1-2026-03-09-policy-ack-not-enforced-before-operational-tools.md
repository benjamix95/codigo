# P1 — policy_ack non era enforced prima dei tool operativi

## Bug Fix Record
- Categoria: A
- Bug: il provider accettava `tool_call_suggested` operativi anche senza `policy_ack` valido, nonostante il bundle policy dichiarasse il marker come obbligatorio prima dei tool.
- Sintomo: il modello poteva partire con tool operativi senza ack esplicito della policy.
- Impatto: enforcement incoerente delle regole AGENTS/policy, con falsa sensazione di guardrail hard.
- Gravita': P1
- Steps to reproduce:
  1. Caricare un workspace con `AGENTS.md`.
  2. Emettere un `tool_call_suggested` operativo senza raw event `policy_ack`.
  3. Osservare l'esecuzione del tool.
- Risultato attuale: il tool operativo veniva eseguito o instradato senza gate hard su `policy_ack`.
- Risultato atteso: prima di ogni tool operativo non esente deve arrivare un `policy_ack` con hash valido.
- Causa probabile: presenza del marker nel prompt bundle, ma assenza del corrispondente blocco duro nel processing dei tool round.
- Scope consentito: `ToolEnabledLLMProvider+SendRoundProcessing`, helper policy correlati, test `ToolEnabledLLMProviderPolicyAckTests`.
- Non-scope: UI chat policy buffering o redesign completo del protocollo eventi.
- Moduli confinanti da verificare: `ToolEnabledLLMProvider+PolicyHelpers`, `ToolTraceVisibility`, normalizzazione eventi `policy_ack`.
- Test da aggiungere o aggiornare: regression test che blocchi `tool_call_suggested` operativo senza ack.
- Strategia di fix minimo: rifiutare i tool operativi finche' il round non ha emesso un `policy_ack` con hash richiesto.
- Verifica post-fix: build workspace + aggiornamento test `ToolEnabledLLMProviderPolicyAckTests+PolicyAck`.
- Commit previsto: `fix(policy): require policy ack before operational tools`
