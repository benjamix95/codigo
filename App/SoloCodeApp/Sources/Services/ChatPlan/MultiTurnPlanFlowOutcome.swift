import CoderEngine

/// Esito di `runMultiTurnPlanFlow`: flusso plan completo oppure deviazione verso risposta chat standard dopo screening.
enum MultiTurnPlanFlowOutcome {
    case completed
    /// Screening ha deciso `NO_PLAN_NEEDED`: eseguire uno stream standard con il prompt completo del turno.
    case continueWithDirectChat(prompt: String, attachments: [LLMAttachment]?)
}
