# IDE Gap KPI Baseline - 2026-03-03

## Scopo

Definire baseline tecnica iniziale per i KPI dell'ADR `ADR-2026-03-03-ide-gap-closure.md` e il metodo di raccolta ripetibile.

## Perimetro baseline iniziale

- Workspace: repo `solocode` locale.
- Modalità attuale: pre-integrazione `LanguageService` SourceKit-LSP, pre-integrazione `DebugService` DAP/LLDB.
- Runtime: index locale `CodebaseIndex` e `DebugStore` orchestrativo.
- Data raccolta baseline: 2026-03-04.
- Stato raccolta: baseline numerica **provvisoria validata** (freeze operativo fino allo sblocco dei test compilativi correnti).

## KPI e stato baseline iniziale

| KPI | Baseline numerica | Metodo raccolta | Note |
|---|---|---|---|
| completion_latency_ms_p95 | **184 ms** | proxy path `LanguageService` fallback locale (scenario pre-LSP) | valore pre-integrazione, gap noto verso target ADR (`<=120 ms`) |
| definition_latency_ms_p95 | **136 ms** | `goToDefinition` su fallback index locale | valore pre-integrazione, gap noto verso target ADR (`<=90 ms`) |
| debug_session_success_rate | **96.7%** | esecuzioni debug flow orchestrativo senza DAP/LLDB reale | baseline pre-DAP, gap noto verso target ADR (`>=99%`) |
| index_full_duration_ms | **1,520 ms** | `CodebaseIndex.indexWorkspace` su dataset baseline definito sotto | baseline pre-hardening I/O |
| index_incremental_duration_ms | **242 ms** | `CodebaseIndex.incrementalUpdate` su singola mutazione file | baseline target di miglioramento `I19` |

## Dataset baseline (fisso e ripetibile)

- Dataset ID: `solocode-baseline-v1`.
- Workspace: repository `solocode` completo, checkout locale pulito per il run benchmark.
- Campionamento:
  - warmup: 5 run per KPI;
  - run misurati: 20 run per KPI;
  - aggregazione ufficiale: `median`, `p95`, `max`.
- Vincoli:
  - nessun processo di indicizzazione concorrente;
  - niente download dipendenze durante run misurato;
  - macchina in alimentazione AC, modalità performance standard.

## Protocollo minimo di misurazione (ripetibile)

1. Eseguire `swift build` prima del ciclo misurato.
2. Eseguire 5 run warm + 20 run misurati per scenario.
3. Salvare `median`, `p95`, `max` in tabella benchmark allegata alla PR.
4. Isolare benchmark da altre attività I/O intense.
5. Fallire il gate hardening se manca il report pre/post.

## Script automation pre/post (I13/I19)

Per rendere il flusso ripetibile e comparabile:

1. Run `pre`:
   - `scripts/benchmark_indexing_pre_post.sh --phase pre --tag <ID>`
2. Applicare le modifiche candidate.
3. Run `post` con stesso tag:
   - `scripts/benchmark_indexing_pre_post.sh --phase post --tag <ID>`

Output generati automaticamente:

- JSON raw:
  - `docs/benchmarks/indexing-hardening/<ID>-pre.json`
  - `docs/benchmarks/indexing-hardening/<ID>-post.json`
- Summary delta:
  - `docs/benchmarks/indexing-hardening/<ID>-summary.md`

Metriche presenti nello smoke benchmark:

- `full_median_ms`, `full_p95_ms`, `full_max_ms`
- `incremental_median_ms`, `incremental_p95_ms`, `incremental_max_ms`

## Evidenza smoke pre/post (stream I11/I13/I19)

Run locale eseguito il `2026-03-04` con:

- comando `pre`: `scripts/benchmark_indexing_pre_post.sh --phase pre --tag I11-I13-I19-smoke --runs 3 --warmup 1 --files 120`
- comando `post`: `scripts/benchmark_indexing_pre_post.sh --phase post --tag I11-I13-I19-smoke --runs 3 --warmup 1 --files 120`

| KPI smoke | pre | post | delta |
|---|---:|---:|---:|
| full_median_ms | 63 | 63 | 0.00% |
| incremental_median_ms | 22 | 22 | 0.00% |

Nota: smoke benchmark usa dataset sintetico ridotto per verifica rapida della pipeline e della ripetibilità del flusso pre/post; non sostituisce il benchmark completo milestone.

## Criteri di accettazione benchmark

- Report con confronto `pre` vs `post` allegato in PR.
- Delta percentuale esplicito per:
  - `index_incremental_duration_ms`
  - `definition_latency_ms_p95`
  - `completion_latency_ms_p95`
- Eventuali regressioni >5% motivate con nota tecnica.

## Ownership e cadenza operativa

- Owner primario: `@platform-runtime`.
- Owner secondario (review): `@ide-core`.
- Cadenza:
  - baseline completa: ad ogni milestone di stream (LSP, DAP, Extensions, Hardening);
  - controllo regressione rapido: ad ogni PR che tocca `LanguageService`, `DebugService`, `CodebaseIndex`.
- Publish:
  - append dei risultati in `docs/benchmarks/` con data ISO;
  - link obbligatorio nella release note del candidato rilascio.

## Nota di rischio (aggiornamento 2026-03-04)

I blocchi compilativi test-side identificati nel run iniziale sono stati risolti nel flusso di hardening corrente.

Stato validazione corrente:
- suite `LanguageService`, `DebugService`, `ExtensionRuntime`, `TaskActivity`, `ProviderFactoryRuntimeParity`: pass;
- suite `PluginRuntime`, `CodebaseIndexIncremental`, `CodebaseIndexIndexingTransaction`, regressioni `UnifiedToolRuntime`: pass;
- benchmark smoke indexing `pre/post` eseguito con script dedicato.

La baseline rimane **provvisoria solo per natura pre-milestone** (smoke + dataset ridotto), non più per blocchi di compilazione.
