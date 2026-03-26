import CoderEngine

/// Esito di `runMultiTurnPlanFlow`: flusso plan completo oppure deviazione verso risposta chat standard dopo screening.
enum MultiTurnPlanFlowOutcome {
    case completed
    /// Screening ha deciso `NO_PLAN_NEEDED`: eseguire uno stream standard con il prompt completo del turno.
    case continueWithDirectChat(prompt: String, attachments: [LLMAttachment]?)
}

/// Esito fase 1 del flusso multi-turn plan: stop o proseguire con domande.
enum MultiTurnPlanAfterPhase1 {
    case finished(MultiTurnPlanFlowOutcome)
    case continuePhase2(analysisText: String)
}

