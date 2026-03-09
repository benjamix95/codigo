# P2 — assenza di enforcement hard del limite file `<300` righe

## Sintomo
Il repo aveva solo una regola documentale sul frazionamento dei file, senza un gate automatico che bloccasse i file di codice toccati oltre 300 righe.

## Impatto
- crescita silenziosa dei file critici
- manutenzione piu' difficile
- rischio di refactor mascherati dentro fix piccoli

## Root cause probabile
Mancava uno stage strutturale dedicato alla dimensione dei file e una baseline separata per il debito legacy.

## Fix applicato
- introdotto `CodeSizeStage`
- fail hard sui file di codice nuovi o toccati oltre 300 righe
- tolleranza limitata ai legacy untouched o ai legacy ridotti senza crescita ulteriore
- aggiunta baseline documentata dei file oversized

## Regressione da coprire
- file nuovo a 301 righe deve fallire
- file legacy gia' fuori soglia che cresce deve fallire
- file a 299/300 righe deve passare
