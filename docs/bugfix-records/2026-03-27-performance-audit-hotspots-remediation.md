# Performance Audit Remediation

Data: 2026-03-27
Ambito: validation/build loop, stream runtime chat, debug logging, polling secondari, workspace scan, persistenza ledger

## Priorita P0

### Validation/build loop troppo costoso
- Categoria: A
- Bug: `scripts/solocode-validate` ricreava cache temporanee, rifaceva package resolution e build debug ridondante prima dei test.
- Sintomo: developer loop lento, doppia compilazione, test serializzati senza motivo.
- Impatto: tempo di validazione alto e churn inutile su Xcode/SPM.
- Scope consentito: `scripts/solocode-validate`, `scripts/build-xcode-stable.sh`, helper shell, test validation.
- Strategia di fix minimo: cache persistenti, package resolve condizionale, `build-for-testing` come build primaria dei targeted tests, `parallel-testing-enabled YES`, `build Release` mantenuta solo per `ciFull`.
- Stato: fixed

## Priorita P1

### Stream runtime chat con troppi hop `MainActor`
- Categoria: A
- Bug: il path `text delta/raw/completed` flushava testo e raw troppo spesso, con file monolitico oltre soglia.
- Sintomo: jank potenziale su stream densi e costo alto per burst raw consecutivi.
- Impatto: CPU/UI churn durante streaming chat.
- Scope consentito: `ConversationFlowCoordinator` e test relativi.
- Strategia di fix minimo: split del file in moduli <=300 righe, batching dei raw consecutivi, policy per non flushare il testo su ogni raw minimo.
- Stato: fixed

### DebugLogServer con write amplification
- Categoria: B
- Bug: apertura/chiusura file handle e creazione `JSONEncoder` ad ogni append.
- Sintomo: I/O sincrono amplificato sul path di logging runtime/debug.
- Impatto: overhead su logging caldo.
- Scope consentito: `DebugLogServer` e test runtime engine.
- Strategia di fix minimo: riuso `JSONEncoder`, cache dei file handle, chiusura controllata prima dei rewrite.
- Stato: fixed

### Ledger usage account persistito ad ogni append
- Categoria: B
- Bug: serializzazione completa dell’array eventi su ogni singola mutazione.
- Sintomo: `UserDefaults` riscritto continuamente durante sessioni con molte usage events.
- Impatto: overhead CPU/I/O evitabile.
- Scope consentito: `CLIAccountUsageLedgerStore` e test store.
- Strategia di fix minimo: debounce breve della persistenza mantenendo formato e compatibilita.
- Stato: fixed

## Priorita P2

### Polling login e LLDB troppo aggressivi
- Categoria: B
- Bug: loop a intervallo fisso per login CLI/Codex e buffer LLDB.
- Sintomo: wakeup frequenti anche in attesa passiva.
- Impatto: CPU sprecata in flussi secondari.
- Scope consentito: `CodexLoginService`, `CLIAccountLoginCoordinator+Flow`, `LLDBPersistentSession`.
- Strategia di fix minimo: backoff condivisa per login e backoff progressivo per il poll del buffer LLDB.
- Stato: fixed

### Workspace scanner full-scan ricorsiva
- Categoria: B
- Bug: `WorkspaceScanner.listSourceFiles` traversava ricorsivamente il filesystem anche in repo Git.
- Sintomo: review scope più lenta su workspace grandi.
- Impatto: I/O locale non necessario nei flussi review/codebase.
- Scope consentito: `WorkspaceScanner` e test workspace.
- Strategia di fix minimo: fast-path `git ls-files --cached --others --exclude-standard`, fallback alla scansione ricorsiva solo fuori da repo Git.
- Stato: fixed

## Rischi Residui

- `CodeReviewSessionState.snapshot()` continua a produrre snapshot completi; non è stato modificato in questa tranche perché richiede un intervento più ampio sul contratto Rust/UI.
- `PlanHistoryStore` e `CLIAccountsStore` mantengono persistenza full-snapshot ma non stanno sul path più caldo coperto dai test di questa tranche.
