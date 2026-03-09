# 2026-03-09 — Code review rigor fixes

## Modifiche
- resa conservativa la promozione `candidate -> verified`: niente promozione automatica con `file_evidence_search` o `semantic_risk_match` deboli
- BugHunter ora usa l'identita' canonica del commit primario e non dichiara piu' preview/apply/commit riusciti senza validare lo stato reale della patch
- irrigidito il patch workflow review: `review_apply_patch` richiede patch preparata e verificata, `applyPatch` rifiuta artifact non verificati, preview/apply espongono piu' contesto del finding
- aggiunto enforcement hard di `policy_ack` prima dei tool operativi non esenti
- reso il warmup MCP additivo sul registry per ridurre perdita/staleness della tool surface
- ridotto il rumore dell'audit `bug_nil_crash_paths` eliminando il matcher grezzo su `!`
- aggiunti regression test per verifier, patch workflow guard, run identity BugHunter, registry merge, policy ack e audit noise

## Motivazione
- la pipeline prometteva in piu' punti garanzie piu' forti di quelle realmente applicate
- servivano fix confinati che aumentassero rigore e prevedibilita' senza rifare l'architettura

## Verifica
- `xcodebuild build -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'CoderIDEMCPServer' -destination 'platform=macOS'`
- `xcodebuild build -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- tentativi di `xcodebuild test` sui target mirati bloccati dallo scheme/test plan corrente: `SoloCodeAppTests` e `CoderEngineTests` non risultano membri eseguibili dello scheme `Solo Code-IntegrationTests` in questo ambiente
