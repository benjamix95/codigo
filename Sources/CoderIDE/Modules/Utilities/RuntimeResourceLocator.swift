import Foundation

enum RuntimeResourceLocator {
    static func appLogoURL() -> URL? {
        resourceURL(named: "AppLogo", withExtension: "png")
    }

    static func appIconURL() -> URL? {
        resourceURL(named: "Codigo", withExtension: "icns")
    }

    static func fontsDirectoryURL() -> URL? {
        directoryURL(named: "Fonts")
    }

    private static let knownBundles: [Bundle] = discoverBundles()

    private static func resourceURL(named name: String, withExtension ext: String?) -> URL? {
        for bundle in knownBundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        let basename = ext.map { "\(name).\($0)" } ?? name
        let fileManager = FileManager.default
        for bundle in knownBundles {
            guard let resourceRoot = bundle.resourceURL else { continue }
            let candidate = resourceRoot.appendingPathComponent(basename, isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func directoryURL(named name: String) -> URL? {
        for bundle in knownBundles {
            if let url = bundle.url(forResource: name, withExtension: nil),
               isDirectory(at: url) {
                return url
            }
            guard let resourceRoot = bundle.resourceURL else { continue }
            let candidate = resourceRoot.appendingPathComponent(name, isDirectory: true)
            if isDirectory(at: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isDirectory(at url: URL) -> Bool {
        var isDirectoryFlag = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectoryFlag)
        return exists && isDirectoryFlag.boolValue
    }

    private static func discoverBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        var seenPaths: Set<String> = []

        func add(_ bundle: Bundle?) {
            guard let bundle else { return }
            let canonicalPath = bundle.bundleURL.resolvingSymlinksInPath().path
            guard seenPaths.insert(canonicalPath).inserted else { return }
            bundles.append(bundle)
        }

        add(Bundle.main)
        Bundle.allBundles.forEach(add)
        Bundle.allFrameworks.forEach(add)

        let scanRoots: [URL?] = [
            Bundle.main.bundleURL,
            Bundle.main.resourceURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
        ]

        for root in scanRoots {
            guard let root else { continue }
            addImmediateBundleChildren(from: root, to: &bundles, seenPaths: &seenPaths)
        }

        return bundles
    }

    private static func addImmediateBundleChildren(
        from root: URL,
        to bundles: inout [Bundle],
        seenPaths: inout Set<String>
    ) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for entry in entries where entry.pathExtension == "bundle" {
            guard let bundle = Bundle(url: entry) else { continue }
            let canonicalPath = bundle.bundleURL.resolvingSymlinksInPath().path
            guard seenPaths.insert(canonicalPath).inserted else { continue }
            bundles.append(bundle)
        }
    }
}
