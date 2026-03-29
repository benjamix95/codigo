# Changelog — 2026-03-29 — Pipeline raw-event hot path e bridge event IDs

## Sommario
- ridotto lavoro duplicato nel path `rawEventHandler` della pipeline
- evitati `textReplace` ridondanti per `assistant_update` già visibile
- ridotte allocazioni di stringhe nel bridge eventi `AgentWorkerEventBridge`

## File toccati
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `Engine/CoderEngine/Sources/AgentPipeline/Bridge/AgentWorkerEventBridge.swift`
- `Tests/SoloCodeAppTests/PipelineIntegrationServiceTests.swift`

## Dettagli
### Pipeline raw events
- quando esiste un `rawEventHandler` esterno, `PipelineIntegrationService` non inoltra più envelope/task activity locali aggiuntive
- `assistant_update` usa ora la stessa policy di promozione del main chat stream per evitare replace inutili quando il testo visibile contiene già il payload

### Agent worker bridge
- aggiunto builder centralizzato per `eventId` e `idempotencyKey`
- sostituita la string interpolation ripetuta nel path caldo con concatenazione su `sequenceString` precomputata

### Test
- aggiunto test che verifica la soppressione delle side-effect `TaskActivity` quando il callback raw esterno è proprietario del path
- aggiunto test che verifica la deduplicazione di `assistant_update` quando il payload è già contenuto nel testo visibile
