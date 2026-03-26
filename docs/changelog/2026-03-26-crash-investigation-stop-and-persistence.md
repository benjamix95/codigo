# Changelog — 2026-03-26 — Crash Investigation: Stop Button & Persistence Bootstrap

## Sommario

Investigazione approfondita di due crash correlati:
1. **EXC_BREAKPOINT su `dispatchPrecondition`** in `ManagedPostgresService.bootstrapIfNeeded()` — già fixato nel commit `d61ad6d83`
2. **Rust `from_raw_parts::precondition_check`** — crash che avviene quando l'utente preme Stop nel composer della chat

## Attività svolte

### 1. Audit completo del layer FFI Swift-Rust

- Verificato che **tutte le 26+ funzioni `extern "C"`** nel Rust FFI usano i wrapper sicuri `with_json_input` / `with_raw_json_input` con null-check
- Nessuna vulnerabilità trovata nel boundary FFI
- File auditati: `Native/RustCore/src/ffi/*.rs` (27 file), `Native/AppCoreRust/src/*.rs` (5 file)

### 2. Tracciamento completo del flusso di cancellazione

Mappato l'intero percorso dal bottone Stop fino al Rust runtime:

```
Stop Button (ChatComposerView+ComposerBox.swift:198)
    ↓ onStop()
interruptTask() (ChatPanelView+PartE_ExecutionControl.swift:5)
    ├── executionController.terminate() — KILLA IL PROCESSO OS
    ├── pipelineIntegrationService.cancelCurrentJob()
    │       ├── runtime.activeStreamTask?.cancel()
    │       └── facade.cancel() → stop orchestrator + worker pool
    └── cancelRunTask() — cancella task tool runtime
        ↓
continuation.onTermination (RustMainChatProviderAdapter.swift:148)
    ├── driver.cancel()
    └── cancelSessionBridge() → Rust cancel_session()
```

### 3. Analisi del session management Rust

- `session.rs`: Thread-safe con `Mutex<HashMap<String, ProviderSessionHandle>>`
- `cancel_session`: Imposta `cancelled = true` atomicamente, non fa cleanup immediato
- `poll_session`: Controlla status terminale e fa cleanup
- Nessuna race condition interna al Rust

### 4. Identificazione root cause del crash Rust

**Race condition nell'ordine di cancellazione:**
- `executionController.terminate()` killa il child process **prima** che `cancelSessionBridge()` notifichi il Rust
- Il worker Rust è bloccato su `BufReader.read_line()` dalla pipe stdout
- La pipe si chiude bruscamente → dati corrotti → `from_raw_parts` precondition fail

### 5. Documentazione bug

Creato report dettagliato: `docs/bugs/P0-2026-03-26-rust-from-raw-parts-crash-on-stop.md`

## Bug documentati

| ID | Priorità | Descrizione | Stato |
|----|----------|-------------|-------|
| P0-2026-03-26-rust-from-raw-parts | P0 | Crash Rust `from_raw_parts` quando si preme Stop nel composer | Documentato, fix proposto |

## Fix implementato

### Inversione ordine di cancellazione

**File modificati:**

1. **`ChatPanelView+PartE_ExecutionControl.swift`** — `interruptTask()` ora chiama `cancelCurrentJob()` e `cancelRunTask()` prima di `executionController.terminate()`. Il processo OS viene killato come fallback dopo la notifica Rust.

2. **`RustMainChatProviderAdapter.swift`** — In `onTermination`, `cancelSessionBridge()` viene chiamato prima di `driver.cancel()`, garantendo che il Rust worker thread veda il flag `cancelled` prima dell'interruzione del poll loop.

3. **`RustMainChatProviderAdapterTests.swift`** — Aggiunto test di regressione `testCancelSessionBridgeFiresBeforeDriverCancel()` che verifica l'ordine corretto di cancellazione.

## File investigati

| File | Scopo dell'investigazione |
|------|--------------------------|
| `ManagedPostgresService.swift` | Verificare stato del fix dispatchPrecondition |
| `PersistenceBootstrapService.swift` | Verificare assenza di dispatchPrecondition |
| `MCPSharedState+PersistenceBridge.swift` | Punto di ingresso bootstrap dal MCP |
| `PostgresPersistenceStore.swift` | Flusso ensureReady → bootstrapIfNeeded |
| `RustMainChatProviderAdapter.swift` | Bridge provider con poll/cancel loop |
| `RustMainChatStoreAdapter.swift` | Store adapter per UI state |
| `RustSearchFFIClient.swift` | FFI bridge core (dlopen, call, free) |
| `Native/RustCore/src/ffi/main_chat.rs` | FFI entry points Rust per chat |
| `Native/RustCore/src/ffi/common.rs` | Wrapper FFI con null-check |
| `Native/RustCore/src/main_chat/providers/session.rs` | Session management con Mutex |
| `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs` | Runner CLI Codex |
| `Native/RustCore/src/main_chat/providers/cli/process.rs` | Subprocess stream management |
| `Native/RustCore/src/main_chat/providers/cli/codex.rs` | Entry point Codex CLI |
| `Native/RustCore/src/main_chat/providers/cli/claude.rs` | Entry point Claude CLI |
| `ChatPanelView+PartE_ExecutionControl.swift` | Handler Stop button |
| `PipelineIntegrationService.swift` | Pipeline cancellation orchestration |
| `PipelineFacade.swift` | Facade cancel (stop orchestrator + workers) |
| `ExecutionController.swift` | OS process termination |
