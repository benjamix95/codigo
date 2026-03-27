# Changelog — 2026-03-27 — Shimmer footer streaming e blocco Thinking in chat

## Problema

- Nella **chat** il testo del footer in streaming (“Thinking”, “Planning next move”, dettaglio operativo) e il titolo **Thinking** nel blocco reasoning sembravano **senza shimmer**, mentre in altri pannelli l’effetto era percepibile o coerente.
- Due fenomeni sovrapposti: contrasto visivo debole e **aggiornamento dell’animazione** non garantito dentro la lista messaggi.

## Modifiche principali

### 1. `TextShimmerEffect` — sweep affidabile e più leggibile

**File:** `App/SoloCodeApp/Sources/Tasking/Views/Shared/TaskActivityShimmer.swift`

- Gradient e `blendMode` adattati al tema (dark/light) per leggere meglio su testo `tertiary` / quaternario.
- **`TimelineView(.animation)`** al posto di `@State` + `withAnimation(.repeatForever)`: il ridisegno segue un tick esplicito e non dipende solo dal sistema di animazione implicita (utile dentro **`ScrollView`**).
- Rispetto di **`accessibilityReduceMotion`**: con riduzione movimento attiva lo shimmer non viene applicato.
- (Commit iniziale) `compositingGroup()`, larghezza minima per la geometria dell’overlay, riavvio su cambio tema.

### 2. Thinking — titolo leggibile in streaming

**File:** `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Thinking.swift`

- In streaming, titolo “Thinking…” usa **`textSecondary`** invece del solo tint oro quasi trasparente sul testo, così il **mask** dello shimmer ha glyf visibili e l’effetto si nota.
- Anteprima riga: in live **`textTertiary`** invece di `textQuaternary` dove applicabile.

### 3. Chat turn — niente `Equatable` sulle view del turno

**File:** `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`

- **`ChatTurnView`** e **`ChatTurnSegmentView`** non sono più `Equatable`.
- Motivazione: con `Equatable`, SwiftUI poteva **saltare il `body`** per molti frame consecutivi durante lo streaming quando i campi del confronto restavano uguali; l’animazione dello shimmer (e il `TimelineView` annidato) non veniva aggiornata come previsto **solo nella chat**.
- Rimosso **`ChatTurnLiveCardFingerprint`** (usato solo per l’uguaglianza delle card swarm nel `==`).

## Riferimenti commit (ordine cronologico)

1. Miglioramento contrasto Thinking + prima iterazione `TextShimmerEffect` (gradiente, compositing, ecc.).
2. Fix dedicato alla chat: `TimelineView` + rimozione `Equatable` su `ChatTurnView` / `ChatTurnSegmentView`.

Verifica locale consigliata: `xcodebuild -scheme "Solo Code" -destination 'platform=macOS' build`.

## Note / trade-off

- Il costo è un **leggero aumento** di rivalutazioni SwiftUI su turn complessi rispetto alla versione con `Equatable` sul turno intero. Se servono micro-ottimizzazioni, si può valutare un equatable **parziale** (solo sotto-alberi statici), mantenendo fuori dal confronto footer streaming e blocchi reasoning live.
