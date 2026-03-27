import SwiftUI

// MARK: - Streaming Cursor

struct StreamingCursorView: View {
    var body: some View {
        // Keep the cursor stateless. Re-entrant layout during startup was
        // crashing while SwiftUI copied the previous @State-backed view.
        Text("\u{258C}")
            .font(.system(size: 13.5))
            .foregroundStyle(Color.primary.opacity(0.35))
            .accessibilityHidden(true)
    }
}
