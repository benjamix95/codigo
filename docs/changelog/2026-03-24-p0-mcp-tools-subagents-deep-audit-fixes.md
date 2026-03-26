# Changelog — P0 Fix: MCP Tools & Sub-Agents Deep Audit

**Data:** 2026-03-24
**Scope:** Fix di 7 bug P0 critici identificati nell'audit approfondito dei tool MCP e dell'infrastruttura sub-agent.

---

## Fix applicati

### 1. `chrono_like_to_unix` — implementazione reale del parsing ISO 8601
- **File:** `Native/CoderideMCPServerRust/src/shared_review_state.rs`
- **Prima:** stub che ritornava sempre `0.0` → tutti i timestamp delle snapshot errati.
- **Dopo:** parsing reale di 8 formati ISO 8601 (con/senza timezone, con/senza millisecondi, formato UTC, formato con offset). Fallback su parsing f64 diretto per timestamp Unix numerici.
- **Dipendenza aggiunta:** `chrono = "0.4"` in `Cargo.toml`.
- **Impatto:** le comparazioni temporali tra snapshot di review/bughunter ora funzionano correttamente. `resolve_active_review_snapshot` e `resolve_active_bughunter_snapshot` selezionano la snapshot più recente.

### 2. `debug_clean` — pattern allineati al formato reale di `debug_mark`
- **File:** `Native/CoderideMCPServerRust/src/debug_tools.rs`
- **Prima:** cercava `"DEBUG[marker]"` ma `debug_mark` inserisce `"[DEBUG:marker]"`. I pattern non matchavano mai.
- **Dopo:** pattern corretti a `"[DEBUG:marker]"`, `"[DEBUG:log]"`, `"[DEBUG:assert]"`, etc. Il fallback `"all"` usa `"[DEBUG:"` per catturare ogni tipo.
- **Impatto:** la pulizia selettiva dei marker di debug ora funziona per tutti i tipi.

### 3. `uuid_like` / `generate_id` — ID univoci con contatore atomico
- **File:** `Native/CoderideMCPServerRust/src/review_tools.rs`, `debug_tools.rs`
- **Prima:** ID basati solo su timestamp → collisioni su chiamate nello stesso ms.
- **Dopo:**
  - `uuid_like()`: aggiunto `AtomicU64` counter → formato `"{timestamp_hex}-{seq_hex}"`.
  - `generate_id()`: aggiunto `AtomicU64` counter → formato `"{prefix}-{ms}-{seq_hex}"`.
- **Impatto:** eliminata la possibilità di collisioni ID per sessioni review/security/bughunter e log entries.

### 4. `write_todos` — append invece di overwrite
- **File:** `Native/CoderideMCPServerRust/src/shared_state.rs`
- **Prima:** `write_json_array(vec![item])` sovrascriveva l'intero file todo con un solo elemento.
- **Dopo:** `read_todos()` → append nuovo item → `write_json_array(existing)`.
- **Impatto:** aggiungere un todo singolo non distrugge più quelli esistenti.

### 5. Timeout subagent inline parametrizzato per ruolo
- **File:** `Engine/.../Subagents/ToolEnabledLLMProvider+SubagentExecutionStream.swift`
- **Prima:** timeout hardcoded `300_000_000_000` nanosecondi (5 min) per tutti i ruoli.
- **Dopo:** usa `SubagentCLIConfig.timeout(for: role)` → bugHunter ottiene 3600s, explorer/reviewer 95s, coder/debugger 110s.
- **Impatto:** il bugHunter inline non viene più ucciso prematuramente a 5 minuti.

### 6. `SubagentTimeoutError` con informazioni di ruolo e timeout
- **File:** `Engine/.../Subagents/SubagentExecutionSupport.swift`
- **Prima:** messaggio generico "5 minutes".
- **Dopo:** messaggio specifico con nome ruolo e durata reale del timeout.

### 7. `SubagentExecutionLimiter` — fix race condition nel counting
- **File:** `Engine/.../Subagents/SubagentExecutionSupport.swift`
- **Prima:** `release()` decrementava `running` e poi faceva `resume()` del waiter, che in un turn successivo incrementava `running`. Nella finestra tra decremento e incremento, un altro `acquire()` poteva ottenere un extra slot → `maxConcurrent + 1` task.
- **Dopo:** `release()` NON decrementa `running` quando c'è un waiter — lo slot viene trasferito direttamente. Il waiter NON incrementa `running` dopo il resume. Il contatore resta stabile durante tutta la transizione.
- **Impatto:** il limite di concorrenza dei subagent viene ora rispettato rigorosamente.

---

## Verifica

- `cargo check` → compilazione OK (1 warning pre-esistente su `read_bughunter_snapshot` non usato).
- `cargo test` → **17/17 test passati**, 0 falliti.
- Build Swift → da verificare con Xcode.

---

## Documentazione correlata

- Indice bug completo: `docs/bugs/P0-2026-03-24-mcp-tools-subagents-deep-audit-index.md`
- 10 file P0, 16 file P1, 1 batch P2-P3, 4 analisi architetturali in `docs/bugs/`.
