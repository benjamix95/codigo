# P2 — Chat inline trace used a linear feed that masked tool identity

## Sintomo

Nella chat principale il trace operativo veniva renderizzato come feed lineare separato, con righe “card-like” prima del testo del messaggio e con iconografia troppo generica.

Effetti osservabili:

- il trace non seguiva il flusso del testo assistente come nello stile desiderato;
- a task finito non si ricompattava in un sommario inline;
- tool distinti come `read`, `write`, `find_symbol`, `semantic_search` risultavano visivamente appiattiti;
- `semantic_search` poteva sembrare “mai usata” perché il feed lineare la mostrava come ricerca generica.

## Impatto

Impatto UX medio:

- riduce leggibilità e fiducia sul trace reale dei tool;
- rende più difficile distinguere discovery strutturata vs grep/search generico;
- allontana la chat dal formato operativo richiesto.

## Causa probabile

`ChatTurnView` usava un renderer lineare locale invece del trace inline specializzato già presente in `MessageToolTraceView`.

In parallelo, il mapping icone/titoli nel feed lineare non preservava bene l’identità dei tool e non evidenziava `semantic_search`.

## Fix applicato

- la chat usa il trace inline specializzato subito sotto il testo assistente;
- il trace si ricompatta automaticamente a fine task;
- il mapping delle icone tool è stato centralizzato nel renderer del trace;
- il sommario collassato è stato allineato all’italiano.

## Verifica

- test mirati `MessageToolTraceMCPCamelCaseTests`;
- test mirati `MessageToolTraceToolIdentityTests`;
- esecuzione `xcodebuild test` sul target `SoloCodeAppTests` con `** TEST SUCCEEDED **`.
