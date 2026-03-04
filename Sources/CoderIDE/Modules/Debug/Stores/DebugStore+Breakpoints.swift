import Foundation

extension DebugStore {
    // MARK: - Breakpoint Management

    func addBreakpoint(filePath: String, line: Int, condition: String? = nil) {
        if let index = breakpoints.firstIndex(where: { bp in
            bp.filePath == filePath && bp.line == line && bp.condition == condition
        }) {
            breakpoints[index].isActive = true
            syncNativeConfiguration()
            return
        }

        let bp = DebugBreakpoint(filePath: filePath, line: line, condition: condition)
        breakpoints.append(bp)
        syncNativeConfiguration()
    }

    func removeBreakpoint(id: UUID) {
        breakpoints.removeAll { $0.id == id }
        syncNativeConfiguration()
    }

    func toggleBreakpoint(id: UUID) {
        guard let idx = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[idx].isActive.toggle()
        syncNativeConfiguration()
    }
}
