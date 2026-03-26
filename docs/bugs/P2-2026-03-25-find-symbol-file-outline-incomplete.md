# P2 — find_symbol e file_outline: Parsing incompleto per linguaggi non-Swift

**Data**: 2026-03-25
**Categoria**: C — Minore
**Scope**: Native/CoderideMCPServerRust/src/search_tools.rs

---

## BUG-9: find_symbol copre solo keyword Swift

**File**: search_tools.rs:107-111

Regex: `\b(class|struct|enum|protocol|func|let|var)\s+<query>\b`

Mancano: `fn`, `impl`, `mod`, `trait` (Rust), `def` (Python), `function`, `const` (JS/TS), `type` (Go)

## BUG-10: file_outline parsing primitivo

**File**: search_tools.rs:128-141

Cerca solo `import|class|struct|enum|protocol|func` con `starts_with`. Non cattura:
- `private func`, `public class`, `internal struct`
- `extension`, `actor`, `typealias`
- Metodi indentati dentro class/struct
- Decoratori (`@objc`, `@MainActor`)

## Fix proposto

Estendere il regex di find_symbol per includere keyword multi-linguaggio.
Per file_outline, usare un parser più robusto o almeno regex con access modifier opzionali.
