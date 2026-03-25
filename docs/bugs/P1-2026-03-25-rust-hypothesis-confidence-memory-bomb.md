# P1 — Rust debug_tools: hypothesis confidence reset + collect_debug_files memory bomb

## Bug fixati

### P1-1: debug_hypothesize confidence reset a 50 su update
- **File**: `debug_tools.rs` riga 362, 430
- **Bug**: `confidence` parsato da stringa con `unwrap_or(50)` — se l'utente non passa confidence nell'update, viene resettato a 50 invece di preservare il valore esistente
- **Impatto**: perdita del valore confidence dell'utente ad ogni update di hypothesis
- **Fix**: `confidence_parsed` è `Option<i64>`. Su `propose` usa `unwrap_or(50)`, su `update` applica solo se `Some`

### P1-2: collect_debug_files memory bomb
- **File**: `debug_tools.rs` riga 1188-1205
- **Bug**: `fs::read_to_string(&path).is_ok()` legge l'intero contenuto di ogni file nel workspace solo per verificarne la leggibilità — alloca GB su workspace con binari pesanti
- **Impatto**: OOM crash o allocazione massiva di memoria
- **Fix**:
  - Usa `path.metadata().len()` invece di leggere il file
  - Aggiunto limite `MAX_DEBUG_FILE_SIZE = 1MB`
  - Aggiunto limite `MAX_DEBUG_FILES = 500`
  - Skip directory nascoste, node_modules, target, build
