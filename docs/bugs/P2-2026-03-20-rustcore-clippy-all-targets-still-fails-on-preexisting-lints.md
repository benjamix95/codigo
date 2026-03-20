# P2 — `cargo clippy --all-targets -D warnings` su RustCore fallisce per lint preesistenti fuori scope

## Bug Fix Record
- Categoria: B
- Bug: la validazione `cargo clippy --manifest-path Native/RustCore/Cargo.toml --all-targets -- -D warnings` resta rossa per lint storici fuori dal perimetro della tranche 3.
- Sintomo: il run fallisce su warning preesistenti in moduli review e altri file Rust non toccati funzionalmente dalla migrazione provider main-chat.
- Impatto: il gate `clippy -D warnings` del crate `RustCore` non è ancora portabile come criterio di accettazione globale per una tranche confinata.
- Gravità: media
- Steps to reproduce:
  1. eseguire `cargo clippy --manifest-path Native/RustCore/Cargo.toml --all-targets -- -D warnings`
  2. osservare errori come `too_many_arguments`, `result_large_err`, `if_same_then_else`, `question_mark`, `dead_code` in moduli review/non-main-chat
- Risultato attuale: il crate fallisce il gate clippy globale anche quando la tranche tocca solo il dominio main-chat provider.
- Risultato atteso: i lint storici fuori scope devono essere drenati in una hardening tranche dedicata, oppure il gate va segmentato per dominio.
- Causa probabile: accumulo di warning storici nel crate monolitico `RustCore`, non introdotti dalla tranche provider.
- Scope consentito: documentazione e tracciamento del blocker.
- Non-scope: refactor diffuso dei moduli review non correlati alla tranche 3.
- Moduli confinanti da verificare: `review_*`, `todo_state`, `main_chat/plan_runtime`.
- Test da aggiungere o aggiornare: nessuno in questa tranche; serve task dedicato di hardening/clippy cleanup.
- Strategia di fix minimo: registrare il blocker e non mischiare cleanup multi-dominio nel commit della tranche provider.
- Verifica post-fix: confermare che `cargo clippy` resta bloccato da lint fuori scope e non da regressioni nuove del dominio main-chat provider.
- Commit previsto: nessuno in questa tranche; backlog/hardening dedicato.
