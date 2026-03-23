import AppKit
import CoderEngine
import SwiftUI
import Vision
import XCTest
@testable import CoderIDE

final class ComposerRuntimeTimerTests: XCTestCase {
    func testBuildComposerFrozenTimerStateForManualStopAutoHides() {
        let state = buildComposerFrozenTimerState(elapsedSeconds: 95, endedByManualStop: true)
        XCTAssertEqual(state.text, "1:35")
        XCTAssertFalse(state.dismissible)
        XCTAssertEqual(state.autoHideDelay, 2.0)
    }

    func testBuildComposerFrozenTimerStateForNaturalCompletionIsDismissible() {
        let state = buildComposerFrozenTimerState(elapsedSeconds: 125, endedByManualStop: false)
        XCTAssertEqual(state.text, "2:05")
        XCTAssertTrue(state.dismissible)
        XCTAssertNil(state.autoHideDelay)
    }

    func testFormatComposerElapsedClampsNegativeValue() {
        XCTAssertEqual(formatComposerElapsed(-10), "0:00")
    }

    @MainActor
    func testComposerKeepsReviewQuickActionsButNotLegacyCodeReviewCard() {
        _ = NSApplication.shared

        let view = ChatComposerView(
            inputText: .constant(""),
            attachedAttachments: .constant([]),
            isSelectingImage: .constant(false),
            isComposerDropTargeted: .constant(false),
            isConvertingHeic: .constant(false),
            isInputFocused: .constant(false),
            isProviderReady: true,
            isLoading: false,
            planningState: .idle,
            runtimeRunState: .idle,
            runtimeTaskStartDate: nil,
            frozenTimerText: nil,
            frozenTimerDismissible: false,
            isIDEStyle: false,
            activeModeColor: .mint,
            activeModeGradient: LinearGradient(
                colors: [.mint, .teal],
                startPoint: .leading,
                endPoint: .trailing
            ),
            inputHint: "Describe the change",
            providerNotReadyMessage: "",
            quickCommandPresets: [
                .init(
                    id: "review-uncommitted",
                    slash: "review-uncommitted",
                    label: "Full uncommitted audit",
                    prompt: "Run a review for the current uncommitted diff."
                )
            ],
            slashCommandPresets: [],
            reviewModePresets: [
                .init(
                    id: "review-standard",
                    slash: "review-standard",
                    label: "Standard",
                    prompt: "Run the standard review flow.",
                    isSelected: true,
                    icon: "magnifyingglass"
                )
            ],
            showPlanRequestIndicator: false,
            controlsRow: AnyView(EmptyView()),
            voiceState: .idle,
            onSend: {},
            onApplyQuickCommand: { _ in },
            onToggleReviewMode: { _ in },
            onInputTextChanged: { _ in },
            onRunQuickCommand: { _ in },
            onPauseResume: {},
            onStop: {},
            onDismissFrozenTimer: {},
            onVoiceAction: {},
            onOptimizePrompt: {},
            isOptimizingPrompt: false
        )

        let renderedStrings = renderedStrings(from: view)

        XCTAssertTrue(renderedStrings.contains("review-uncommitted"))
        XCTAssertTrue(renderedStrings.contains("Full uncommitted audit"))
        XCTAssertFalse(renderedStrings.contains("Code Review"))
        XCTAssertFalse(renderedStrings.contains("Autofix: analysis + parallel fix workers + test loop"))
        XCTAssertFalse(renderedStrings.contains("Discovery: analysis only, no automatic fixes"))
    }

    @MainActor
    private func renderedStrings<V: View>(from view: V) -> [String] {
        let size = CGSize(width: 1600, height: 700)
        let rootView = view
            .scaleEffect(2, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Unable to create bitmap for ChatComposerView OCR")
            return []
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let cgImage = bitmap.cgImage else {
            XCTFail("Unable to convert bitmap to CGImage for ChatComposerView OCR")
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
        } catch {
            XCTFail("OCR request failed: \(error)")
            return []
        }

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
