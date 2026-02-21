import Foundation
import CoderEngine

enum EditorViewMode: Equatable {
    case plain
    case diffInline
}

/// Store per i file aperti nell'editor, condiviso tra Sidebar, Editor e Chat context.
@MainActor
final class OpenFilesStore: ObservableObject {
    @Published var openFilePath: String?
    @Published private(set) var openPaths: [String] = []
    @Published private(set) var loadErrors: [String: String] = [:]
    @Published private(set) var dirtyPaths: Set<String> = []
    @Published private(set) var pinnedPaths: Set<String> = []
    @Published private(set) var viewModeByPath: [String: EditorViewMode] = [:]
    @Published private(set) var diffByPath: [String: GitFileDiff] = [:]

    private var fileContents: [String: String] = [:]
    private var diskSnapshot: [String: String] = [:]

    func openFile(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        if !openPaths.contains(path) {
            openPaths.append(path)
        }
        openFilePath = path
        if viewModeByPath[path] == nil {
            viewModeByPath[path] = .plain
        }
        ensureLoaded(path)
    }

    func closeFile(_ path: String) {
        if pinnedPaths.contains(path) { return }
        openPaths.removeAll { $0 == path }
        fileContents.removeValue(forKey: path)
        diskSnapshot.removeValue(forKey: path)
        loadErrors.removeValue(forKey: path)
        dirtyPaths.remove(path)
        viewModeByPath.removeValue(forKey: path)
        diffByPath.removeValue(forKey: path)
        if openFilePath == path {
            openFilePath = openPaths.last
        }
    }

    func pinFile(_ path: String, pinned: Bool) {
        if pinned {
            pinnedPaths.insert(path)
        } else {
            pinnedPaths.remove(path)
        }
    }

    func closeOthers(keeping path: String) {
        let keptPaths = openPaths.filter { $0 == path || pinnedPaths.contains($0) }
        let keptSet = Set(keptPaths)
        for stalePath in openPaths where !keptSet.contains(stalePath) {
            fileContents.removeValue(forKey: stalePath)
            diskSnapshot.removeValue(forKey: stalePath)
            loadErrors.removeValue(forKey: stalePath)
            dirtyPaths.remove(stalePath)
            viewModeByPath.removeValue(forKey: stalePath)
            diffByPath.removeValue(forKey: stalePath)
        }
        openPaths = keptPaths
        openFilePath = path
    }

    func activateNextTab() {
        guard let current = openFilePath, let index = openPaths.firstIndex(of: current), !openPaths.isEmpty else {
            openFilePath = openPaths.first
            return
        }
        let nextIndex = (index + 1) % openPaths.count
        openFilePath = openPaths[nextIndex]
    }

    func activatePreviousTab() {
        guard let current = openFilePath, let index = openPaths.firstIndex(of: current), !openPaths.isEmpty else {
            openFilePath = openPaths.first
            return
        }
        let prevIndex = (index - 1 + openPaths.count) % openPaths.count
        openFilePath = openPaths[prevIndex]
    }

    func closeAllFiles() {
        openPaths.removeAll()
        openFilePath = nil
        fileContents.removeAll()
        diskSnapshot.removeAll()
        loadErrors.removeAll()
        dirtyPaths.removeAll()
        pinnedPaths.removeAll()
        viewModeByPath.removeAll()
        diffByPath.removeAll()
    }

    func ensureLoaded(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        guard fileContents[path] == nil else { return }
        reload(path: path)
    }

    func content(for path: String) -> String {
        fileContents[path] ?? ""
    }

    func error(for path: String) -> String? {
        loadErrors[path]
    }

    func isDirty(path: String) -> Bool {
        dirtyPaths.contains(path)
    }

    func updateContent(_ content: String, for path: String) {
        ensureLoaded(path)
        fileContents[path] = content
        let snapshot = diskSnapshot[path] ?? ""
        if content == snapshot {
            dirtyPaths.remove(path)
        } else {
            dirtyPaths.insert(path)
        }
        loadErrors[path] = nil
    }

    @discardableResult
    func save(path: String) -> Bool {
        let content = fileContents[path] ?? ""
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            diskSnapshot[path] = content
            dirtyPaths.remove(path)
            loadErrors[path] = nil
            return true
        } catch {
            loadErrors[path] = "Impossibile salvare il file: \(error.localizedDescription)"
            return false
        }
    }

    func reload(path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            fileContents[path] = content
            diskSnapshot[path] = content
            dirtyPaths.remove(path)
            loadErrors[path] = nil
        } catch {
            fileContents[path] = ""
            diskSnapshot[path] = ""
            dirtyPaths.remove(path)
            loadErrors[path] = "Impossibile aprire il file: \(error.localizedDescription)"
        }
    }

    func viewMode(for path: String) -> EditorViewMode {
        viewModeByPath[path] ?? .plain
    }

    func diff(for path: String) -> GitFileDiff? {
        diffByPath[path]
    }

    func setViewMode(_ mode: EditorViewMode, for path: String) {
        viewModeByPath[path] = mode
    }

    func setPlainMode(path: String) {
        viewModeByPath[path] = .plain
    }

    func openFileWithDiff(_ absolutePath: String, gitRoot: String, gitService: GitService) {
        openFile(absolutePath)
        let rootURL = URL(fileURLWithPath: gitRoot).standardizedFileURL
        let fileURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
        let rootPath = rootURL.path
        let filePath = fileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            loadErrors[absolutePath] = "Il file selezionato non appartiene al repository corrente"
            viewModeByPath[absolutePath] = .plain
            return
        }
        let relative = String(filePath.dropFirst(rootPath.count + 1))
        do {
            let patch = try gitService.fileDiff(gitRoot: gitRoot, path: relative)
            diffByPath[absolutePath] = patch
            viewModeByPath[absolutePath] = .diffInline
        } catch {
            loadErrors[absolutePath] = error.localizedDescription
            viewModeByPath[absolutePath] = .plain
        }
    }

    func openFilesForContext(maxFiles: Int = 8, maxCharsPerFile: Int = 12_000, linkedPaths: [String] = []) -> [OpenFile] {
        var result: [OpenFile] = []
        var seen = Set<String>()

        if let current = openFilePath,
           let content = fileContents[current] {
            result.append(OpenFile(path: current, content: String(content.prefix(maxCharsPerFile))))
            seen.insert(current)
        }

        if result.count >= maxFiles {
            return result
        }

        for path in dirtyPaths.sorted() where path != openFilePath {
            guard let content = fileContents[path] else { continue }
            result.append(OpenFile(path: path, content: String(content.prefix(maxCharsPerFile))))
            seen.insert(path)
            if result.count >= maxFiles { break }
        }

        if result.count < maxFiles {
            for path in linkedPaths where !seen.contains(path) {
                let content = fileContents[path] ?? loadContextContentFromDisk(path: path)
                guard let content else { continue }
                result.append(OpenFile(path: path, content: String(content.prefix(maxCharsPerFile))))
                seen.insert(path)
                if result.count >= maxFiles { break }
            }
        }

        if result.count < maxFiles {
            for path in openPaths.reversed() where !seen.contains(path) {
                guard let content = fileContents[path] else { continue }
                result.append(OpenFile(path: path, content: String(content.prefix(maxCharsPerFile))))
                if result.count >= maxFiles { break }
            }
        }

        return result
    }

    private func loadContextContentFromDisk(path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        fileContents[path] = content
        diskSnapshot[path] = content
        loadErrors[path] = nil
        return content
    }
}
