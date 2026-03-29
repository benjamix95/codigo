# P1 - query umane instradate male e grep fallback sovra-usato nel search stack

## Bug Fix Record
- Categoria: A
- Bug: le query search senza nome tool esplicito venivano inferite troppo spesso come `grep` o `web_search`, mentre `semantic_search` lanciava comunque il grep fallback anche quando l'indice aveva gia' risultati sufficienti.
- Sintomo: le query umane ("where is auth handled", "error handling flow") non mostravano un uso coerente del semantic/vector search; il flusso risultava meno istantaneo del previsto e il beneficio del DB vettoriale appariva nascosto.
- Impatto: degrado diretto di latenza, perdita di precisione nel routing search, percezione errata che il semantic search non venisse usato.
- Gravita: alta
- Steps to reproduce:
  1. Emettere un tool payload con solo `query` e senza nome tool esplicito.
  2. Osservare che l'inferenza cade su `grep`/`web_search` invece di `semantic_search`.
  3. Eseguire `semantic_search` su un workspace con risultati indicizzati gia' sufficienti.
  4. Verificare che il runtime continui comunque a popolare il grep fallback/cache.
- Risultato attuale: routing ambiguo a monte e fallback testuale eseguito troppo spesso a valle.
- Risultato atteso: query umane instradate a `semantic_search`; grep fallback usato solo come rete di sicurezza quando l'indice non basta davvero.
- Causa probabile: euristica `query -> grep/web_search` troppo generica in `ToolEnabledLLMProvider`; policy fallback nel runtime semantic priva di short-circuit sui risultati indicizzati.
- Scope consentito:
  - `Engine/CoderEngine/Sources/ProviderBackends/Shared/ToolEnabledLLMProvider/Tools/*`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Index/Search/Semantic/*`
  - test `Tests/CoderEngineTests/*` relativi a provider/runtime search
- Non-scope:
  - refactor globale del sistema prompt
  - cambi strutturali al DB Postgres/pgvector oltre alla diagnostica
  - UI timeline/trace
- Moduli confinanti da verificare:
  - tool inference provider-side
  - semantic search runtime
  - search health check / telemetry
- Test da aggiungere o aggiornare:
  - regressione su inferenza query -> `semantic_search`
  - regressione su skip del grep fallback quando i risultati indicizzati bastano
  - health check con stato vector/trigram/embedding
- Strategia di fix minimo:
  - introdurre euristiche dedicate per query umane
  - short-circuit del grep fallback su risultati indicizzati sufficienti
  - ampliare `search_health_check` per esporre lo stato del ramo vettoriale
- Verifica post-fix:
  - suite mirata `ToolEnabledLLMProviderPolicyAckTests`
  - suite mirata `UnifiedToolRuntimeTests`
  - controllo payload `search_health_check`
- Commit previsto: `fix(search): prefer semantic routing and trim grep fallback`
