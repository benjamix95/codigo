# P0 — Rust `from_raw_parts::precondition_check` crash on Stop

## Bug Fix Record

- **Categoria**: A — Critico
- **Bug**: Crash `EXC_BREAKPOINT` in Rust `core::slice::raw::from_raw_parts::precondition_check` quando l'utente preme Stop nel composer della chat
- **Sintomo**: L'app crasha con `EXC_BREAKPOINT (code=1, subcode=0x10…)` nello stack frame `core::slice::raw::from_raw_parts::precondition_check`
- **Impatto**: Crash completo dell'app — perdita del contesto chat corrente
- **Gravità**: P0 — crash bloccante su azione utente comune

## Steps to reproduce

1. Avviare una sessione chat con un provider CLI (Codex, Claude CLI, Gemini CLI)
2. Attendere che il provider inizi a generare output
3. Premere il bottone **Stop** nel composer
4. L'app crasha

## Risultato attuale

Crash con stack trace:
```
core::slice::raw::from_raw_parts::precondition_check
```
Il file sorgente Rust non è disponibile nel debugger:
```
Can't show source file for stack frame 0:
/rustc/.../library/core/src/ub_checks.rs
```

## Risultato atteso

L'app deve interrompere la generazione in modo pulito, mostrare "[Interrupted by user]" e tornare allo stato idle senza crash.

## Causa probabile

Race condition nel flusso di cancellazione tra Swift e Rust:

### Flusso di cancellazione (tracciato)

1. **UI**: Bottone Stop → `onStop()` callback
2. **ChatPanel**: `interruptTask(for:)` in `ChatPanelView+PartE_ExecutionControl.swift:5-45`
3. **ExecutionController**: `terminate(scope:)` → **killa il processo OS del provider CLI**
4. **Pipeline**: `pipelineIntegrationService.cancelCurrentJob()` → cancella stream + facade
5. **Provider**: `continuation.onTermination` → `driver.cancel()` + `cancelSessionBridge()`

### Punto critico

Il passo 3 (`executionController.terminate()`) killa il processo child **prima** che il Rust venga notificato della cancellazione (passo 5). Questo causa:

1. Il worker thread Rust è bloccato su `read_json_line()` in `codex_app_server.rs:718-728` (BufReader.read_line dalla pipe stdout del child)
2. Il processo child viene killato esternamente dalla parte Swift
3. La pipe stdout si chiude in modo brusco — i buffer interni di BufReader possono contenere dati parziali/corrotti
4. Contemporaneamente, `onTermination` in `RustMainChatProviderAdapter.swift:148-153` chiama sia `driver.cancel()` che `cancelSessionBridge()` sullo stesso thread
5. Il poll loop (riga 89-145) potrebbe essere ancora in esecuzione quando `cancelSessionBridge` viene invocato, creando due chiamate FFI concorrenti verso Rust

### Perché `from_raw_parts`

Il `from_raw_parts::precondition_check` è un assert di debug Rust che verifica che il puntatore non sia nullo e sia correttamente allineato. Questo si attiva quando:
- Un buffer interno (Vec/String) viene acceduto dopo che i suoi dati sono stati invalidati
- Tipicamente durante deserializzazione JSON (serde_json) di dati corrotti dalla pipe troncata
- O durante operazioni su String che derivano dalla lettura della pipe interrotta

## Scope consentito

- `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderAdapter.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_ExecutionControl.swift`
- `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`
- `Native/RustCore/src/main_chat/providers/cli/process.rs`

## Non-scope

- Modifica del session management Rust (già thread-safe con Mutex)
- Refactor del flusso di cancellazione complessivo
- Provider API (OpenAI, Anthropic, Google) — diverso path di esecuzione

## Moduli confinanti da verificare

- `PipelineIntegrationService.cancelCurrentJob()`
- `PipelineFacade.cancel()`
- `ExecutionController.terminate()`

## Strategia di fix proposta

### Opzione A — Ordine di cancellazione (Preferita)
Invertire l'ordine: notificare il Rust della cancellazione **prima** di killare il processo OS:

1. `cancelSessionBridge()` → Rust imposta `cancelled = true`
2. Il worker Rust controlla `is_cancelled()` e esce dal loop di lettura
3. Solo dopo, `executionController.terminate()` killa il processo se ancora vivo

### Opzione B — Guard nel onTermination
Nel `RustMainChatProviderAdapter.swift:148-153`, attendere che il poll loop (driver Task) termini prima di chiamare `cancelSessionBridge()`:

```swift
continuation.onTermination = { _ in
    driver.cancel()
    // Attendere che il driver Task termini
    // prima di chiamare cancel sul Rust
    Task {
        _ = await driver.value
        let _ = self.cancelSessionBridge(...)
    }
}
```

### Opzione C — Catch panic nel Rust
Wrappare le operazioni critiche nel worker thread con `std::panic::catch_unwind` per prevenire crash propagati alla parte Swift.

## Test da aggiungere

1. Test che simula cancellazione durante lettura dalla pipe
2. Test di concorrenza: poll + cancel simultanei
3. Test che il processo child viene killato correttamente dopo la cancellazione Rust

## File correlati investigati

| File | Ruolo |
|------|-------|
| `RustMainChatProviderAdapter.swift` | Bridge Swift-Rust per provider sessioni |
| `ChatPanelView+PartE_ExecutionControl.swift` | Handler del bottone Stop |
| `PipelineIntegrationService.swift` | Orchestrazione cancellazione pipeline |
| `RustSearchFFIClient.swift:281-335` | FFI bridge Swift → Rust (RustSearchFFIApi) |
| `Native/RustCore/src/main_chat/providers/session.rs` | Session management Rust (Mutex-protected) |
| `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs` | Runner CLI Codex con BufReader |
| `Native/RustCore/src/main_chat/providers/cli/process.rs` | Subprocess management generico |
| `Native/RustCore/src/ffi/common.rs` | FFI input validation (null check OK) |
