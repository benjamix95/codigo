# Deep Audit MCP Tools + Sub-Agents — 2026-03-25

## Scope dell'analisi

Analisi approfondita di:
- **Rust MCP Server**: tutti i 20 file in `Native/CoderideMCPServerRust/src/`
- **Swift Sub-Agents**: pipeline in `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Subagents/`
- **Swift AgentPipeline**: `Engine/CoderEngine/Sources/AgentPipeline/`

---

## RIEPILOGO

| Gravità | Rust MCP | Swift Sub-Agents | Totale |
|---------|----------|-------------------|--------|
| **P0**  | 6        | 6                 | **12** |
| **P1**  | 8        | 8                 | **16** |
| **P2**  | 9        | 3                 | **12** |
| **ARCH**| 0        | 2                 | **2**  |
| **TOT** | **23**   | **19**            | **42** |

---

## P0 — CRITICI (12)

### RUST

#### R-P0-01: Race condition read-modify-write su TUTTI i file JSON
- **File**: `shared_state.rs:108-115`, `shared_review_state.rs:208-214`, `plan_state.rs:629-650`
- **Problema**: `write_json_array()`, `write_json()`, `write_document()` non hanno file locking. Race condition: Thread A legge, Thread B legge+scrive, Thread A scrive → perdita dati di B.
- **Impatto**: Perdita di todos, comandi review, plan steps in concorrenza
- **Fix**: Implementare `flock()` o write atomico con `rename()` da file temporaneo

#### R-P0-02: Generazione ID non univoci (`uuid_like_seed`)
- **File**: `shared_state.rs:166-173`
- **Problema**: ID basato su hash XOR del titolo. Due todo con stesso titolo → stesso ID → sovrascrittura
- **Impatto**: Perdita dati silente
- **Fix**: Usare `uuid::Uuid::new_v4()` o counter atomico + timestamp

#### R-P0-03: `generated_conversation_id()` collisione timestamp
- **File**: `plan_state.rs:674-690`
- **Problema**: UUID-like generato da nanos epoch. Due richieste stesso nanosecondo → ID uguale
- **Impatto**: Collision di conversation ID, corruzione plan state
- **Fix**: Aggiungere random bytes o usare UUID v4

#### R-P0-04: `regex_replace()` usa string literal match, non regex
- **File**: `edit_tools.rs:130-162`
- **Problema**: `content.replace(&pattern, &replacement)` — literal string, non regex
- **Impatto**: Tool MCP `regex_replace` non funziona per nessun pattern regex
- **Fix**: Usare `regex::Regex::new(pattern)?.replace_all(...)`

#### R-P0-05: Path traversal — nessun boundary check
- **File**: `file_tools.rs:24-27`
- **Problema**: `resolve_path()` non verifica che il path sia dentro workspace
- **Impatto**: Lettura/scrittura file arbitrari (`../../etc/passwd`)
- **Fix**: Verificare `path.canonicalize()` è dentro `workspace.canonicalize()`

#### R-P0-06: `write_todos()` distrugge todos concorrenti
- **File**: `shared_state.rs:55-105`
- **Problema**: Read-modify-write senza lock. Scrittura concorrente perde todos dell'altro thread
- **Impatto**: Perdita dati utente
- **Fix**: File locking atomico

### SWIFT

#### S-P0-01: SubagentExecutionLimiter — overcounting (maxConcurrent+1)
- **File**: `SubagentExecutionSupport.swift:29-70`
- **Problema**: `release()` resume waiter ma decrementa `running` PRIMA che il waiter ri-incrementi. Window di race: un nuovo `acquire()` ottiene slot extra.
- **Impatto**: 4 subagent concorrenti quando il limite è 3, sovra-allocazione token LLM
- **Fix**: Non decrementare `running` quando c'è un waiter — trasferimento diretto dello slot

#### S-P0-02: SubagentLiveState — perdita eventi live
- **File**: `ToolEnabledLLMProvider+SubagentExecutionStream.swift:52-205`
- **Problema**: `group.next()` + `group.cancelAll()` nel `withThrowingTaskGroup` — se il task di streaming completa quasi contemporaneamente al timeout, gli ultimi eventi emessi vengono persi
- **Impatto**: Stato incompleto dei subagent card, risultati troncati
- **Fix**: Raccogliere tutti gli eventi prima di cancellare il group

#### S-P0-03: EventDeliveryManager — deadlock su waitingKeys
- **File**: `EventDeliveryManager.swift:124-145`
- **Problema**: `drainWaitingQueue()` chiamata dentro delivery task concorrenti modifica `waitingKeys` contemporaneamente
- **Impatto**: Eventi pendenti rimangono per sempre, delivery bloccata
- **Fix**: Serializzare il drain in un singolo punto di responsabilità

#### S-P0-04: WorkerPool — race condition su delegate deallocazione
- **File**: `WorkerPool.swift:249-265`
- **Problema**: Weak delegate deallocato tra check `if let` e uso → risultato va in `pendingResults` senza notifica
- **Impatto**: Task completati mai ritirati dall'orchestrator (perdita silenziosa)
- **Fix**: Se delegate è nil, loggare e garantire collectResults()

#### S-P0-05: Per-task timeout calculation inversione logica
- **File**: `OrchestratorMainLoop.swift:247`
- **Problema**: `perTaskTimeoutMs = max(job.jobTimeoutMs / taskCount, 30_000)` — 10 task × 30s = 300s, supera il jobTimeout di 60s
- **Impatto**: Task timeout più alto del job timeout, lock holding indefinito
- **Fix**: `remainingMs = jobTimeoutMs - elapsedMs; perTask = remainingMs / remainingCount`

#### S-P0-06: Lock leak in OrchestratorMainLoop+Scheduling
- **File**: `OrchestratorMainLoop+Scheduling.swift:33-52`
- **Problema**: Se lock acquisita appena prima di timeout ma dispatch avviene comunque, `release()` non è nel path di cleanup
- **Impatto**: Lock leak → deadlock potenziale
- **Fix**: Usare `defer { lockManager.release(taskId:) }` subito dopo acquisizione

---

## P1 — IMPORTANTI (16)

### RUST

| ID | File | Problema |
|----|------|----------|
| R-P1-01 | `debug_tools.rs:434` | Logic error `\|\|` vs `&&` su root_cause_type — sovrascrive con stringa vuota |
| R-P1-02 | `plan_state.rs:663-664` | `iso_now()` genera `ts-123...` non ISO 8601 — parsing fallisce ovunque |
| R-P1-03 | `shared_review_state.rs:242-272` | `chrono_like_to_unix()` è stub con 8 formati errati, fallback a `parse::<f64>()` |
| R-P1-04 | `web_tools.rs:27-39` | Timeout hardcoded 20s, non configurabile, exit code non gestito |
| R-P1-05 | `search_tools.rs:300-319` | `glob_like_match` non gestisce `*` iniziale — `*.rs` non matcha |
| R-P1-06 | `plan_state.rs:517` | Step ID = indice (1,2,3) — collision dopo riordino |
| R-P1-07 | `diagnostics_tools.rs:31-44` | Build senza timeout, fallback a `swift build` senza verificare |
| R-P1-08 | `web_tools.rs:80-95` | HTML strip troppo semplice, manca `&lt;`, `&gt;`, tag malformati |

### SWIFT

| ID | File | Problema |
|----|------|----------|
| S-P1-01 | `SubagentExecutionStream.swift:197-200` | Timeout hardcoded 300s vs 3600s bugHunter — mismatch config |
| S-P1-02 | `SubagentExecutionLiveState.swift:73-83` | Array eventi senza limite → OOM su loop di output |
| S-P1-03 | `EventDeliveryManager.swift:76-78` | `deliveryTasks` memory leak se processDelivery lancia prima di defer |
| S-P1-04 | `OrchestratorMainLoop+ResultHandling.swift:7-12` | Lock release senza verificare ownership → doppio release |
| S-P1-05 | `TaskCompletionHandler.swift:44` | Jitter seed hardcoded `42` → thundering herd su retry |
| S-P1-06 | Vari | Timeout inconsistenti tra CLI config, orchestrator, stream (300/3600/30000) |
| S-P1-07 | `SubagentExecutionLiveState.swift:97-99` | Output troncato senza warning |
| S-P1-08 | `EventBus.swift:231-249` | idempotency cache leak su sessioni lunghe |

---

## P2 — MINORI (12)

### RUST

| ID | File | Problema |
|----|------|----------|
| R-P2-01 | `shared_state.rs:6-53` | Status default hardcoded "pending" senza validazione |
| R-P2-02 | `debug_tools.rs:195-198` | `let _ = write_store()` ignora errori → log loss |
| R-P2-03 | `plan_state.rs:650` | `let _ = write_document()` ignora errori → plan changes silently lost |
| R-P2-04 | `shared_review_state.rs:157-159` | `reference_seconds()` confusione epoch types |
| R-P2-05 | Tutti i file | Nessun test per race conditions, timestamp parsing, ID collisions |
| R-P2-06 | `debug_tools.rs` | `write_store()` ignora errori multipli con `let _ =` |
| R-P2-07 | Tutti | Pattern `let _ =` su operazioni I/O critiche (>15 occorrenze) |
| R-P2-08 | `shared_state.rs` | Nessun backup/rollback su write failure |
| R-P2-09 | `plan_state.rs` | Nessuna validazione dei dati in input (string vuote, JSON malformato) |

### SWIFT

| ID | File | Problema |
|----|------|----------|
| S-P2-01 | `SubagentExecutionLiveState.swift:97-99` | Output truncation silente senza evento |
| S-P2-02 | `EventBus.swift:231-249` | idempotency cache slow leak su long sessions |
| S-P2-03 | `DeadLetterQueue.swift:125-127` | FIFO eviction senza priority-based |

---

## ARCHITETTURALI (2)

| ID | Problema |
|----|----------|
| ARCH-01 | Dual-storage (Postgres + JSON) senza transazione atomica → inconsistenza |
| ARCH-02 | Timeout definiti in >5 posti senza coordinamento centrale |

---

## ORDINE DI FIX SUGGERITO

1. **R-P0-04** regex_replace broken — fix immediato, 5 min
2. **R-P0-05** path traversal — security, 10 min
3. **R-P0-02** uuid_like_seed collision — 15 min
4. **R-P0-01** file locking — architetturale, 1h
5. **S-P0-01** SubagentLimiter overcounting — 30 min
6. **S-P0-05** per-task timeout inversione — 15 min
7. **S-P0-06** lock leak scheduling — 20 min
8. Tutti i P1 in batch successivo
