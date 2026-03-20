import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    // MARK: - Phase-Specific Plan Prompts

    internal func buildPhase0ScreeningPrompt(userRequest: String) -> String {
        planRuntimeAction(
            "plan_prepare_phase0_screening_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase1AnalysisPrompt(userRequest: String) -> String {
        planRuntimeAction(
            "plan_prepare_phase1_analysis_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPostClarificationAnalysisPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        if planClarificationAnswers != clarificationAnswers {
            _ = planRuntimeAction(
                "plan_apply_clarification_answers",
                text: clarificationAnswers,
                shouldRunInline: planShouldRunInline
            )
        }
        return planRuntimeAction(
            "plan_prepare_post_clarification_analysis_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase2QuestionPrompt(userRequest: String, analysisContext: String) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        return planRuntimeAction(
            "plan_prepare_phase2_questions_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase3GenerationPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        if planClarificationAnswers != clarificationAnswers {
            _ = planRuntimeAction(
                "plan_apply_clarification_answers",
                text: clarificationAnswers,
                shouldRunInline: planShouldRunInline
            )
        }
        return planRuntimeAction(
            "plan_prepare_phase3_generation_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase3TodoComplianceRepairPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String,
        invalidPlanOutput: String
    ) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        if planClarificationAnswers != clarificationAnswers {
            _ = planRuntimeAction(
                "plan_apply_clarification_answers",
                text: clarificationAnswers,
                shouldRunInline: planShouldRunInline
            )
        }
        return planRuntimeAction(
            "plan_prepare_phase3_repair_prompt",
            text: invalidPlanOutput,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }
}
