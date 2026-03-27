import Foundation
import os

/// Mantiene le `capacity` string lessicograficamente più piccole viste nello stream (max-heap interno).
private struct LexicographicSmallestStringBuffer {
    private var heap: [String]
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.heap = []
        self.heap.reserveCapacity(self.capacity)
    }

    mutating func consider(_ value: String) {
        guard capacity > 0 else { return }
        if heap.count < capacity {
            heap.append(value)
            siftUp(heap.count - 1)
        } else if value < heap[0] {
            heap[0] = value
            siftDown(0)
        }
    }

    mutating func drainSortedAscending() -> [String] {
        heap.sort()
        return heap
    }

    private mutating func siftUp(_ index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if heap[i] <= heap[parent] { break }
            heap.swapAt(i, parent)
            i = parent
        }
    }

    private mutating func siftDown(_ index: Int) {
        var i = index
        while true {
            let left = 2 * i + 1
            var largest = i
            if left < heap.count, heap[left] > heap[largest] {
                largest = left
            }
            let right = left + 1
            if right < heap.count, heap[right] > heap[largest] {
                largest = right
            }
            if largest == i { break }
            heap.swapAt(i, largest)
            i = largest
        }
    }
}

extension CodebaseIndex {
    /// Raccoglie path relativi per il panel review in **una sola** transizione actor (evita migliaia di `await` dal chiamante).
    /// Comportamento equivalente al vecchio loop `allIndexedFilePaths` + `getFileNode` + filtro sorgente.
    public func gatherSourcePathsForPanelReview(
        promptCap: Int,
        auditCap: Int
    ) -> (promptPaths: [String], workspaceIncludedPaths: [String]) {
        let take = max(0, auditCap)
        guard take > 0 else { return ([], []) }

        // Niente `keys.sorted()` su tutto l'indice né `sort()` su tutte le sorgenti qualificate:
        // su repo grandi m≈n ⇒ decine di secondi. I primi `take` path qualificati in ordine lessicografico
        // si ottengono con heap di dimensione fissa: O(n log take), memoria O(take).
        let t0 = Date()
        let indexedCount = indexedFiles.count
        var buffer = LexicographicSmallestStringBuffer(capacity: take)
        for rel in indexedFiles.keys {
            if let node = allFileNodes[rel] {
                guard node.isSourceFile else { continue }
            }
            buffer.consider(rel)
        }
        let indexedSources = buffer.drainSortedAscending()
        let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
        if elapsedMs > 800 {
            CodebaseIndex.logger.info("gatherSourcePathsForPanelReview slow: indexedFiles=\(indexedCount) take=\(take) ms=\(elapsedMs)")
        }
        guard !indexedSources.isEmpty else { return ([], []) }

        let pCap = max(0, promptCap)
        let promptPaths = Array(indexedSources.prefix(pCap))
        return (promptPaths, indexedSources)
    }
}
