import CoreGraphics

enum ContentPanelWidthPolicy {
    static let minPanelWidth: CGFloat = 300

    static func maxWidth(
        detailWidth: CGFloat,
        fraction: CGFloat,
        minWidth: CGFloat = minPanelWidth
    ) -> CGFloat {
        let safeDetailWidth = detailWidth.isFinite ? max(0, detailWidth) : 0
        return max(minWidth, safeDetailWidth * fraction)
    }

    static func clampedWidth(
        storedWidth: Double,
        detailWidth: CGFloat,
        fraction: CGFloat,
        minWidth: CGFloat = minPanelWidth
    ) -> CGFloat {
        let maxWidth = maxWidth(detailWidth: detailWidth, fraction: fraction, minWidth: minWidth)
        let candidate = CGFloat(storedWidth)
        guard candidate.isFinite, candidate > 0 else { return minWidth }
        return min(max(candidate, minWidth), maxWidth)
    }

    /// All’apertura di un pannello aggancia la larghezza salvata al massimo consentito per la geometria corrente.
    static func snapStoredWidthToOpenMax(
        storedWidth: inout Double,
        detailWidth: CGFloat,
        fraction: CGFloat,
        minWidth: CGFloat = minPanelWidth
    ) {
        let cap = maxWidth(detailWidth: detailWidth, fraction: fraction, minWidth: minWidth)
        storedWidth = Double(cap)
    }
}
