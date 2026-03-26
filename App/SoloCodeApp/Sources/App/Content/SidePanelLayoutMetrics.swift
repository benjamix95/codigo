import Foundation

/// Larghezze min/max dei pannelli laterali nel `ChatPanelView` (allineate a `PanelResizeHandle` in `ChatPanelView+RootLayout`).
enum SidePanelLayoutMetrics {
    static let planMin: Double = 220
    static let planMax: Double = 500
    static let debugMin: Double = 240
    static let debugMax: Double = 500
    static let swarmMin: Double = 260
    static let swarmMax: Double = 540
    static let codeReviewMin: Double = 280
    static let codeReviewMax: Double = 560
    static let gitMin: Double = 280
    static let gitMax: Double = 500
}
