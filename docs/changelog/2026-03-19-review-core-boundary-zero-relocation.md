# 2026-03-19 - Review core boundary zero relocation

## Modifiche
- ricollocati i file residui del motore review dal path storico `Engine/CoderEngine/Sources/CodeReview` a `Engine/CoderEngine/Sources/Infrastructure/ReviewCore`
- drenati i sottoblocchi:
  - `Core`
  - `Pipeline`
  - `Session`
- aggiornati i path nel progetto Xcode

## Effetto
- il review-scope strict non conta più file Swift non-UI nel boundary hard-fail del dominio review
- il dominio review boundary è ora a zero nel guard strict; il residuo semantico della migrazione va valutato separatamente dal solo posizionamento dei file

## Verifica prevista
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests+Parsing -only-testing:CoderEngineTests/CodeReviewMultiSwarmProviderTests+TaskExtraction -only-testing:CoderEngineTests/ReviewPipelineCoordinatorTests -only-testing:CoderEngineTests/ReviewSessionRegistryTests -only-testing:CoderEngineTests/CodeReviewSessionStateTests`
- audit strict review-scope
