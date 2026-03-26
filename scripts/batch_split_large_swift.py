#!/usr/bin/env python3
"""Split large Swift sources at verified boundaries (one-shot batch, idempotent)."""

from __future__ import annotations

from pathlib import Path

ROOT = Path("/Users/benjaminstoica/SoloCode")
HDR_UI = """import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

"""


def main() -> None:
    # --- PartD MessagesScroll ---
    d_path = ROOT / "App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessagesScroll.swift"
    d_stack = ROOT / "App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessagesStack.swift"
    d_cell = ROOT / "App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessageCell.swift"
    if d_path.is_file():
        L = d_path.read_text(encoding="utf-8").splitlines(keepends=True)
        assert len(L) == 349, len(L)
        d_stack.write_text("".join(L[0:146]) + "\n}\n", encoding="utf-8", newline="\n")
        d_cell.write_text(HDR_UI + "extension ChatPanelView {\n" + "".join(L[147:349]), encoding="utf-8", newline="\n")
        d_path.unlink()
        print("batch: PartD split")
    elif d_stack.is_file() and d_cell.is_file():
        print("batch: PartD skip (already split)")

    # --- PartE TaskLifecycle ---
    e_path = ROOT / "App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_TaskLifecycle.swift"
    e_a = ROOT / "App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_TaskLifecycle+UI.swift"
    e_b = ROOT / "App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartE_TaskLifecycle+Run.swift"
    if e_path.is_file():
        L = e_path.read_text(encoding="utf-8").splitlines(keepends=True)
        assert len(L) == 350, len(L)
        e_a.write_text("".join(L[0:213]) + "\n}\n", encoding="utf-8", newline="\n")
        e_b.write_text(HDR_UI + "extension ChatPanelView {\n" + "".join(L[214:350]), encoding="utf-8", newline="\n")
        e_path.unlink()
        print("batch: PartE split")
    elif e_a.is_file() and e_b.is_file():
        print("batch: PartE skip (already split)")

    # --- Streaming2 continuation split ---
    c_path = ROOT / "App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2Continuation.swift"
    c_side = ROOT / "App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2Continuation+SideEffects.swift"
    if c_side.is_file() and "handleRawStreamEventContinuationSideEffects" in c_path.read_text(encoding="utf-8"):
        print("batch: Streaming2Continuation skip (already split)")
    else:
        L = c_path.read_text(encoding="utf-8").splitlines(keepends=True)
        assert len(L) == 266, len(L)
        call = """        handleRawStreamEventContinuationSideEffects(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId,
            shouldApplyPipelineArtifacts: shouldApplyPipelineArtifacts,
            shouldUpdateInlineReasoningVisuals: shouldUpdateInlineReasoningVisuals
        )
"""
        head = "".join(L[0:12]) + "".join(L[12:133]) + call + "    }\n}\n"
        c_path.write_text(head, encoding="utf-8", newline="\n")
        side_head = HDR_UI + """extension ChatPanelView {
    internal func handleRawStreamEventContinuationSideEffects(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?,
        shouldApplyPipelineArtifacts: Bool,
        shouldUpdateInlineReasoningVisuals: Bool
    ) {
"""
        c_side.write_text(side_head + "".join(L[133:265]) + "}\n", encoding="utf-8", newline="\n")
        print("batch: Streaming2Continuation split")

    # --- ApplyLifecycle: public structs + SoloCodeApp extension ---
    a_path = ROOT / "App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift"
    models = ROOT / "App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchApplyLifecycleModels.swift"
    solo = ROOT / "App/SoloCodeApp/Sources/CodeReview/Services/SoloCodeApp+ReviewPatchCommands.swift"
    a_txt = a_path.read_text(encoding="utf-8")
    structs_moved_out = "struct ReviewPatchApplyExecutionContext" not in a_txt
    if structs_moved_out and models.is_file() and solo.is_file():
        print("batch: ApplyLifecycle skip (already split)")
    else:
        L = a_txt.splitlines(keepends=True)
        assert len(L) == 493, len(L)
        models.write_text(
            "import CoderEngine\nimport Foundation\n\n" + "".join(L[303:318]),
            encoding="utf-8",
            newline="\n",
        )
        solo.write_text(
            "import CoderEngine\nimport Foundation\n\n" + "".join(L[412:493]),
            encoding="utf-8",
            newline="\n",
        )
        a_path.write_text("".join(L[0:302]) + "".join(L[318:412]), encoding="utf-8", newline="\n")
        print("batch: ApplyLifecycle split")

    # --- Debug pipeline slice inclusion ---
    inc_path = ROOT / "Engine/CoderEngine/Sources/AgentPipeline/Debug/Factory/DebugPipelineSliceInclusion.swift"
    dbg_path = ROOT / "Engine/CoderEngine/Sources/AgentPipeline/Debug/Factory/PipelineJobFactory+Debug.swift"
    dtxt = dbg_path.read_text(encoding="utf-8")
    if "DebugPipelineSliceInclusion" not in dtxt:
        inc_body = """import Foundation

enum DebugPipelineSliceInclusion {
    static func shouldIncludeStage(
        slice: DebugPipelineSlice,
        stage: DebugStageKind,
        request: DebugSessionRequest
    ) -> Bool {
        switch slice {
        case .full:
            return true
        case .intake:
            switch stage {
            case .describePipelineBootstrap, .sessionStart, .gatherContext,
                 .requestClarification, .analyzeIssue, .reproducePipelineBootstrap,
                 .awaitReproduceGate:
                return true
            default:
                return false
            }
        case .investigation:
            switch stage {
            case .hostReproduceGateAck:
                return request.includeNativeStages
            case .nativeStart, .nativeSyncBreakpoints, .nativeSyncWatches,
                 .reproduce, .instrument, .fixPipelineBootstrap, .snapshot,
                 .hypothesize, .fix, .reviewFix, .setVerifyPhase,
                 .verify, .awaitFixGate:
                return true
            default:
                return false
            }
        case .resolution:
            switch stage {
            case .clean, .nativeStop, .timeline, .sessionExport,
                 .resolve, .sessionStop:
                return true
            default:
                return false
            }
        }
    }
}
"""
        inc_path.write_text(inc_body, encoding="utf-8", newline="\n")
        old = """        func shouldInclude(_ stage: DebugStageKind) -> Bool {
            switch slice {
            case .full:
                return true
            case .intake:
                switch stage {
                case .describePipelineBootstrap, .sessionStart, .gatherContext,
                     .requestClarification, .analyzeIssue, .reproducePipelineBootstrap,
                     .awaitReproduceGate:
                    return true
                default:
                    return false
                }
            case .investigation:
                switch stage {
                case .hostReproduceGateAck:
                    return request.includeNativeStages
                case .nativeStart, .nativeSyncBreakpoints, .nativeSyncWatches,
                     .reproduce, .instrument, .fixPipelineBootstrap, .snapshot,
                     .hypothesize, .fix, .reviewFix, .setVerifyPhase,
                     .verify, .awaitFixGate:
                    return true
                default:
                    return false
                }
            case .resolution:
                switch stage {
                case .clean, .nativeStop, .timeline, .sessionExport,
                     .resolve, .sessionStop:
                    return true
                default:
                    return false
                }
            }
        }

"""
        new = """        func shouldInclude(_ stage: DebugStageKind) -> Bool {
            DebugPipelineSliceInclusion.shouldIncludeStage(slice: slice, stage: stage, request: request)
        }

"""
        if old not in dtxt:
            raise SystemExit("PipelineJobFactory+Debug: expected shouldInclude block not found")
        dbg_path.write_text(dtxt.replace(old, new), encoding="utf-8", newline="\n")
        print("batch: DebugPipelineSliceInclusion extracted")
    else:
        print("batch: Debug pipeline skip (already refactored)")

    print("batch_split_large_swift: done")


if __name__ == "__main__":
    main()
