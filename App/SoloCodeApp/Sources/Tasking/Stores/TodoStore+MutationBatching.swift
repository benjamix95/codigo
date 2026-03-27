import Foundation

extension TodoStore {
    func performBatchUpdates(_ updates: () -> Void) {
        mutationBatchDepth += 1
        defer {
            mutationBatchDepth -= 1
            if mutationBatchDepth == 0, needsSaveAfterBatch {
                needsSaveAfterBatch = false
                saveTodos()
            }
        }
        updates()
    }
}
