# ARCH — ID generation non-sicura pervasiva

## Analisi architetturale

### Descrizione
Sia nel Rust MCP server che nello Swift codebase, gli ID vengono generati con metodi basati su timestamp a bassa risoluzione:

- **Rust `uuid_like()`**: `format!("{:x}", reference_seconds_now().to_bits())` — f64 timestamp bits
- **Rust `generate_id()`**: `format!("{prefix}-{}", now_string())` — timestamp millisecondi
- **Rust `uuid_like_seed(title)`**: hash deterministico del titolo — nessun componente random

### Problema
Tutti questi metodi possono produrre collisioni:
- `uuid_like()`: due chiamate nello stesso quantum f64 → stesso ID
- `generate_id()`: due chiamate nello stesso millisecondo → stesso ID
- `uuid_like_seed()`: due todo con lo stesso titolo → stesso ID

### Impatto
- Session ID collisions per review/security/bughunter
- Log entry ID collisions nel debug store
- Todo ID collisions

### Raccomandazione
**Rust:** Usare il crate `uuid` (v4 random) per tutti gli ID di sessione. Per gli ID sequenziali (log entries), usare `AtomicU64` contatore + timestamp.

**Swift:** Verificare che `UUID()` (Foundation) sia usato ovunque servano ID unici.
