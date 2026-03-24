import AppKit
import CoderEngine
import QuickLookUI
import SwiftUI
// MARK: - Backward compat aliases
typealias MessageBubbleView = MessageRow

// MARK: - Streaming Dots

/// Animated dots indicator for streaming state.
///
/// Uses `TimelineView` instead of `Timer.scheduledTimer` to avoid
/// timer lifecycle issues. When a view using `Timer` is rapidly
/// added/removed from the view tree during streaming, timers can
/// leak or accumulate — each firing `withAnimation` and forcing
/// unnecessary redraws. `TimelineView` is managed by SwiftUI's
/// own lifecycle and automatically stops when the view is removed.
struct StreamingDots: View {
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                        .opacity(phase == i ? 1 : 0.25)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
    }
}

// MARK: - Typing Indicator

/// Animated typing indicator with three bouncing dots.
///
/// Same `TimelineView` approach as `StreamingDots` to prevent
/// timer leak during rapid view insertion/removal cycles.
struct TypingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
            let dot = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .opacity(dot == i ? 1 : 0.3)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: dot)
        }
    }
}
