# Oversized File Baseline — 2026-03-09

## Obiettivo
Congelare il debito legacy sui file di codice oltre 300 righe al momento dell'introduzione del gate automatico.

## Regola operativa
- i file legacy gia' oltre soglia e non toccati non bloccano il rollout iniziale
- se un file legacy oltre 300 righe viene toccato e cresce ulteriormente, la validation fallisce
- ogni file nuovo deve restare sotto 300 righe

## Snapshot sintetica
- file di codice oltre 300 righe: 66
- file di codice oltre 500 righe: 6

## Aree principali coinvolte
- test legacy molto estesi in `Tests/CoderEngineTests` e `Tests/SoloCodeAppTests`
- alcuni file runtime/app in `App/SoloCodeApp/Sources`
- alcuni file core engine in `Engine/CoderEngine/Sources`

## Nota
La baseline include solo il debito legacy gia' presente. Asset binari, font e vendor JS di Monaco non rientrano nel gate hard dei file di codice.
