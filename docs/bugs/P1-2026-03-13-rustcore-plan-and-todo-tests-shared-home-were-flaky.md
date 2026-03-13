# P1 - I test Rust `plan_state` e `todo_state` erano flaky per accesso concorrente a `HOME`

## Bug Fix Record
- Categoria: A
- Bug: i test Rust che usano `with_temp_home` serializzavano `HOME` con lock separati per modulo, lasciando corse tra `plan_state` e `todo_state` durante `cargo test`.
- Sintomo: `cargo test --manifest-path Native/RustCore/Cargo.toml` falliva in modo non deterministico con snapshot mancanti o merge inattesi, mentre i singoli test passavano.
- Impatto: pipeline Rust inaffidabile; impossibilita' di accettare commit conformi alla testing policy.
- Gravita': alta, perche' il problema blocca direttamente la validazione obbligatoria del core Rust.
- Steps to reproduce:
  1. Eseguire `cargo test --manifest-path Native/RustCore/Cargo.toml`.
  2. Osservare failure intermittenti in `plan_state::tests::*` e `todo_state::tests::*`.
  3. Rieseguire i singoli test e notare che passano isolati.
- Risultato attuale: test harness concorrente con lock locali per modulo.
- Risultato atteso: un unico lock di processo per i test che mutano `HOME`.
- Causa probabile: i moduli avevano helper `env_lock()` distinti, quindi la mutazione della variabile d'ambiente globale non era realmente serializzata.
- Scope consentito:
  - `Native/RustCore/src/plan_state.rs`
  - `Native/RustCore/src/todo_state.rs`
  - `Native/RustCore/src/test_support.rs`
  - `Native/RustCore/src/lib.rs`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - logica di business del review panel
  - contract FFI del review core
- Moduli confinanti da verificare:
  - suite completa `cargo test --manifest-path Native/RustCore/Cargo.toml`
- Test da aggiungere o aggiornare:
  - nessun nuovo test dedicato; la prova e' la stabilita' della suite completa concorrente
- Strategia di fix minimo:
  - introdurre `test_support::env_lock()`
  - riusare lo stesso lock nei test `plan_state` e `todo_state`
  - rendere univoci gli ID con contatore atomico per evitare collisioni a timestamp ravvicinati
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
- Commit previsto: `fix(rust-core): stabilize plan and todo temp-home tests`
