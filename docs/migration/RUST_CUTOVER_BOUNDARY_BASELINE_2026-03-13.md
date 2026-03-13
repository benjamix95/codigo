# Rust Cutover Boundary Baseline - 2026-03-13

## Stato osservato
- `App/SoloCodeApp/Sources`: circa `750` file Swift, di cui circa `415` non-UI
- `Engine/CoderEngine/Sources`: circa `492` file Swift non-UI
- `Sidebar`: circa `19` file Swift, di cui circa `3` non-UI
- `App/SoloCodeApp/Sources/Panels/CodeReview`: `81` file Swift per circa `12.6k` linee
- `Engine/CoderEngine/Sources/CodeReview`: `49` file Swift per circa `7.7k` linee
- `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `30` file Swift per circa `3.6k` linee
- `Engine/CoderEngine/Sources/Tools`: `71` file Swift per circa `11.1k` linee

## Domini legacy principali da drenare verso Rust
- `App/SoloCodeApp/Sources/Panels/CodeReview`
- `App/SoloCodeApp/Sources/Runtime`
- `Engine/CoderEngine/Sources/CodeReview`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore`
- `Engine/CoderEngine/Sources/Pipeline`
- `Engine/CoderEngine/Sources/Tools`
- `Engine/CoderEngine/Sources/Providers`
- `Engine/CoderEngine/Sources/PersistenceCore`
- `Engine/CoderEngine/Sources/CodebaseIndex`
- `Engine/CoderEngine/Sources/Workspace`

## Freeze iniziale applicato in questa tranche
- i nuovi file Swift devono essere UI, binding minimo o bootstrap Apple e passare l'allowlist `Config/validation/rust-cutover-swift-allowlist.txt`
- i file Swift legacy gia' esistenti vengono censiti come backlog di dominio e possono essere toccati solo per ridurli o svuotarli durante il cutover
- il gate finale "zero Swift non-UI" non e' ancora attivo: questa tranche congela il perimetro, non conclude la migrazione
