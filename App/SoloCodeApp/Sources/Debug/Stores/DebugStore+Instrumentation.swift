import Foundation

extension DebugStore {
    // MARK: - Instrumentation Management

    func addInstrumentation(_ point: InstrumentationPoint) {
        instrumentationPoints.append(point)
    }

    func addInstrumentation(filePath: String, lineNumber: Int, type: InstrumentationPoint.InstrumentationType, code: String, hypothesisId: String? = nil) {
        addInstrumentation(InstrumentationPoint(
            filePath: filePath,
            lineNumber: lineNumber,
            type: type,
            code: code,
            hypothesisId: hypothesisId
        ))
    }

    func removeInstrumentation(id: UUID) {
        instrumentationPoints.removeAll { $0.id == id }
    }

    /// Number of files with instrumentation
    var instrumentedFileCount: Int {
        Set(instrumentationPoints.map(\.filePath)).count
    }

    /// Remove all instrumentation (called by "Mark Fixed")
    func cleanAllInstrumentation() -> [InstrumentationPoint] {
        let points = instrumentationPoints
        instrumentationPoints.removeAll()
        return points
    }
}
