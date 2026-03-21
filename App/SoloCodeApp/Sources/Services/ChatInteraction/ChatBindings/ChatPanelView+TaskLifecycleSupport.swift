import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldRecordFallbackTurnStartEvent(
    isTaskActive: Bool,
    scopedActivityCount: Int
) -> Bool {
    isTaskActive && scopedActivityCount == 0
}
