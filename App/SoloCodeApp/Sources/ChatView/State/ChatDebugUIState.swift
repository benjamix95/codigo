import CoderEngine
import Foundation
import SwiftUI

// MARK: - ChatDebugUIState

/// ObservableObject state container for debug-related UI properties.
/// Extracted from ChatPanelView to reduce @State explosion and isolate re-renders.
/// Uses ObservableObject (not @Observable) for macOS 13.0 compatibility.
@MainActor
final class ChatDebugUIState: ObservableObject {
    @Published var toggleEnabled: Bool = false
    @Published var pendingCodeReviewSessionConfigOverride: SessionConfig?
}
