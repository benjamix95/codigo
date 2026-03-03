import SwiftUI

// MARK: - Streaming Cursor

struct StreamingCursorView: View {
    @State private var visible = true

    var body: some View {
        Text("\u{258C}")
            .font(.system(size: 13.5))
            .foregroundStyle(Color.primary.opacity(visible ? 0.7 : 0.15))
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}
