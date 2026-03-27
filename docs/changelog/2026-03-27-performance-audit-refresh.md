# Changelog — 2026-03-27 Performance Audit Refresh

## Aggiunto

- Nuovo audit prestazionale in `/Users/benjaminstoica/SoloCode/docs/bugs/ARCH-2026-03-27-performance-bottlenecks-refresh.md`.
- Nuovi artefatti benchmark:
  - `/Users/benjaminstoica/SoloCode/docs/benchmarks/indexing-hardening/PERF-AUDIT-20260327-post.json`
  - `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/PERF-AUDIT-20260327-post-engine.json`
  - `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/PERF-AUDIT-20260327-post-app.json`

## Documentato

- L'indicizzazione incrementale attuale non emerge come collo di bottiglia principale (`8 ms` median sul benchmark smoke a 180 file).
- La review core smoke e la proiezione app risultano leggere; i colli di bottiglia residui sono concentrati soprattutto nella chat runtime/UI.
- Le priorita' aggiornate sono:
  - `ChatPanelView` dependency graph troppo ampio
  - bridge `ChatStore` <-> Rust ancora troppo largo
  - `PipelineIntegrationService` con snapshot globali `@Published`
  - `EventBus.publish` seriale
  - persistenza `TodoStore` sincrona

## Nessuna modifica funzionale

- Nessun file di codice applicativo e' stato modificato.
- Nessun comportamento runtime e' stato cambiato in questo passaggio; l'intervento e' solo di audit e documentazione.
