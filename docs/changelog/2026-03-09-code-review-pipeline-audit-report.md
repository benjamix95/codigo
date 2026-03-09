# 2026-03-09 — Code review pipeline audit report

## Modifiche
- aggiunto un report tecnico di audit sulla pipeline di code review, BugHunter, policy, MCP e patch workflow
- registrati i bug prioritizzati emersi dall'analisi in `docs/bugs`
- classificati i punti di determinismo reale, le euristiche e i gap di verifica/test

## Motivazione
- serviva una verifica profonda della pipeline di code review per capire se i controlli siano realmente deterministici e rigorosi o solo apparentemente tali
- i risultati andavano tracciati nel repo in modo leggibile, prioritizzato e revertibile

## Verifica
- analisi statica dei moduli review, audit, BugHunter, provider policy/runtime e MCP
- confronto con i test presenti nel workspace
- consolidamento dei risultati di 8 filoni di analisi parallela
