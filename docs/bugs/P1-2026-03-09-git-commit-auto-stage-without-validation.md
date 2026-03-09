# P1 — commit Git con auto-stage implicito e senza validation uniforme

## Sintomo
Il commit flow locale poteva includere file unstaged tramite `git add -A` implicito e arrivava a `git commit` senza passare da una validation pipeline obbligatoria.

## Impatto
- commit troppo ampi e non chirurgici
- rischio di includere modifiche locali non verificate
- assenza di blocco forte su build/test/security prima del commit

## Root cause probabile
Il commit service e la UI Git erano orientati alla comodita' operativa, non al containment richiesto in fase di stabilizzazione.

## Fix applicato
- `GitService.commit` ora e' staged-only
- `includeUnstaged` non puo' piu' promuovere `git add -A`
- commit bloccato se la validation `gitCommit` fallisce
- hook Git tracked e CI usano lo stesso criterio di gate

## Regressione da coprire
- commit con `includeUnstaged=true` deve fallire subito
- commit senza file staged deve fallire
- commit con validation fallita non deve creare SHA nuovo
