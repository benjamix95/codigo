import Foundation

extension DebugStore {
    // MARK: - Breakpoint Management

    func addBreakpoint(filePath: String, line: Int, condition: String? = nil) {
        let bp = DebugBreakpoint(filePath: filePath, line: line, condition: condition)
        breakpoints.append(bp)
    }

    func removeBreakpoint(id: UUID) {
        breakpoints.removeAll { $0.id == id }
    }

    func toggleBreakpoint(id: UUID) {
        guard let idx = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[idx].isActive.toggle()
    }
}
