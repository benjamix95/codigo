import AppKit
import CoderEngine
import QuickLookUI
import SwiftUI

// MARK: - Reasoning Block Model

struct ReasoningBlock: Identifiable, Equatable {
    let id: String
    var text: String
}

// MARK: - Message Segment Model

enum MessageSegmentKind: Equatable {
    case reasoning(String)
    case text(String)
    case toolTrace([ToolTraceEvent])

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.reasoning(let a), .reasoning(let b)): return a == b
        case (.text(let a), .text(let b)): return a == b
        case (.toolTrace(let a), .toolTrace(let b)): return a.map(\.id) == b.map(\.id)
        default: return false
        }
    }
}

struct MessageSegment: Identifiable {
    let id: String
    var kind: MessageSegmentKind
}
