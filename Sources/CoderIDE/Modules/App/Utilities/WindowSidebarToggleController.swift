import AppKit
import SwiftUI

final class WindowSidebarToggleController {
    private static var controllers: [ObjectIdentifier: WindowSidebarToggleController] = [:]

    static func installIfNeeded(on window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let controller = controllers[key] {
            controller.attachAccessoryIfNeeded()
            controller.updateLayout()
            return
        }

        controllers[key] = WindowSidebarToggleController(window: window)
    }

    static func remove(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        controllers[key]?.stopPeriodicStrip()
        controllers.removeValue(forKey: key)
    }

    private weak var window: NSWindow?
    private let accessoryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var observers: [NSObjectProtocol] = []
    private var titleObservation: NSKeyValueObservation?
    private var titleVisibilityObservation: NSKeyValueObservation?
    private var chatInfo: WindowTitlebarChatInfo?
    /// Periodic timer that strips sidebar buttons SwiftUI re-adds after layout passes.
    private var periodicStripTimer: Timer?

    private init(window: NSWindow) {
        self.window = window
        configureAccessoryHost()
        installTitleObserver(for: window)
        installObservers(for: window)
        attachAccessoryIfNeeded()
        updateAccessoryContent(maxWidth: 0)
        updateLayout()
        startPeriodicStrip()
    }

    deinit {
        stopPeriodicStrip()
        titleObservation?.invalidate()
        titleVisibilityObservation?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Start a repeating timer that continuously strips sidebar buttons and title text.
    /// This catches late SwiftUI re-insertions in IDE mode after columnVisibility changes.
    private func startPeriodicStrip() {
        guard periodicStripTimer == nil else { return }
        periodicStripTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let window = self.window else {
                self?.stopPeriodicStrip()
                return
            }
            self.hideTitlebarSidebarButtons(from: window)
            self.stripAutomaticSidebarToolbarItems(from: window)
            // Kill any toolbar SwiftUI re-creates
            if let toolbar = window.toolbar {
                toolbar.isVisible = false
                for i in stride(from: toolbar.items.count - 1, through: 0, by: -1) {
                    toolbar.removeItem(at: i)
                }
            }
            window.toolbar = nil
            // Force title clear on every tick
            if !window.title.isEmpty { window.title = "" }
            if !window.subtitle.isEmpty { window.subtitle = "" }
            if window.representedURL != nil { window.representedURL = nil }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        }
    }

    private func stopPeriodicStrip() {
        periodicStripTimer?.invalidate()
        periodicStripTimer = nil
    }

    /// KVO: zero out the window title whenever SwiftUI resets it to the app name.
    private func installTitleObserver(for window: NSWindow) {
        titleObservation = window.observe(\.title, options: [.new]) { [weak self] win, _ in
            if !win.title.isEmpty {
                win.title = ""
                win.subtitle = ""
            }
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            // Also scrub any visible title text in the titlebar view hierarchy
            DispatchQueue.main.async { [weak self] in
                self?.hideTitlebarSidebarButtons(from: win)
            }
        }
        // Also observe titleVisibility — SwiftUI may reset it to .visible
        titleVisibilityObservation = window.observe(\.titleVisibility, options: [.new]) { win, _ in
            if win.titleVisibility != .hidden {
                win.titleVisibility = .hidden
                win.title = ""
                win.subtitle = ""
            }
        }
    }

    private func configureAccessoryHost() {
        accessoryHost.isHidden = true
        accessoryHost.setFrameSize(.zero)
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        let windowNotifications: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didMoveNotification,
        ]

        observers = windowNotifications.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.attachAccessoryIfNeeded()
                self?.updateLayout()
            }
        }

        observers.append(
            center.addObserver(
                forName: .windowTitlebarChatInfoDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                self.chatInfo = WindowTitlebarChatInfo(userInfo: notification.userInfo)
                self.attachAccessoryIfNeeded()
                self.updateLayout()
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Self.remove(for: window)
            }
        )
    }

    private func attachAccessoryIfNeeded() {
        guard
            let window,
            let zoomButton = window.standardWindowButton(.zoomButton),
            let titlebarView = zoomButton.superview
        else {
            return
        }

        if accessoryHost.superview !== titlebarView {
            accessoryHost.removeFromSuperview()
            titlebarView.addSubview(accessoryHost)
        }
        stripAutomaticSidebarToolbarItems(from: window)
        hideTitlebarSidebarButtons(from: window)
        // SwiftUI may re-add sidebar toggle after layout passes; strip at multiple delays.
        // Extended delays (1.5, 2.0) catch late re-insertions during IDE mode transitions.
        for delay in [0.0, 0.1, 0.3, 0.6, 1.0, 1.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window else { return }
                self.stripAutomaticSidebarToolbarItems(from: window)
                self.hideTitlebarSidebarButtons(from: window)
                // Ensure toolbar stays invisible
                if let toolbar = window.toolbar {
                    toolbar.isVisible = false
                }
            }
        }
    }

    private func updateLayout() {
        guard
            let window,
            let zoomButton = window.standardWindowButton(.zoomButton),
            let titlebarView = zoomButton.superview
        else {
            return
        }

        let accessoryLeadingX = zoomButton.frame.maxX + 12
        let accessoryWidth = max(0, min(titlebarView.bounds.width * 0.42, titlebarView.bounds.width - accessoryLeadingX - 20))
        updateAccessoryContent(maxWidth: accessoryWidth)
        let accessoryHeight = max(20, accessoryHost.fittingSize.height)
        let accessoryY = round(zoomButton.frame.midY - (accessoryHeight / 2))
        accessoryHost.frame = NSRect(
            x: accessoryLeadingX,
            y: accessoryY,
            width: accessoryWidth,
            height: accessoryHeight
        )
        stripAutomaticSidebarToolbarItems(from: window)
        hideTitlebarSidebarButtons(from: window)
        if let toolbar = window.toolbar {
            toolbar.isVisible = false
        }
    }

    private func updateAccessoryContent(maxWidth: CGFloat) {
        guard let chatInfo, maxWidth > 0 else {
            accessoryHost.rootView = AnyView(EmptyView())
            accessoryHost.isHidden = true
            return
        }

        accessoryHost.rootView = AnyView(
            WindowTitlebarChatAccessoryView(
                info: chatInfo,
                openProject: { [weak self] in
                    guard let path = self?.chatInfo?.projectPath else { return }
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            )
            .frame(width: maxWidth, alignment: .leading)
        )
        accessoryHost.isHidden = false
        accessoryHost.layoutSubtreeIfNeeded()
    }

    private func hideTitlebarSidebarButtons(from window: NSWindow) {
        let toggleAction = NSSelectorFromString("toggleSidebar:")
        // Search in titlebar view hierarchy
        if let titlebarView = window.standardWindowButton(.zoomButton)?.superview {
            hideSidebarButtons(in: titlebarView, action: toggleAction, depth: 8)
            hideTitlebarTitleText(in: titlebarView, depth: 10)
            // Also search the titlebar container (parent of traffic lights)
            if let titlebarContainer = titlebarView.superview {
                hideTitlebarTitleText(in: titlebarContainer, depth: 10)
            }
        }
        // Also search the full content view hierarchy — SwiftUI may place
        // a native sidebar toggle outside the toolbar when columnVisibility
        // is .detailOnly (IDE mode).
        if let contentView = window.contentView {
            hideSidebarButtons(in: contentView, action: toggleAction, depth: 20)
            hideTitlebarTitleText(in: contentView, depth: 18)
        }
        // Walk the NSSplitView hierarchy for stray toggle views
        if let contentView = window.contentView {
            stripSplitViewToggleViews(in: contentView, depth: 10)
        }
    }

    /// Recursively find and nuke any NSSplitView-related toggle views
    /// that SwiftUI inserts for NavigationSplitView sidebar control.
    private func stripSplitViewToggleViews(in view: NSView, depth: Int) {
        guard depth > 0 else { return }
        for subview in view.subviews where subview !== accessoryHost {
            let cls = NSStringFromClass(type(of: subview))
            // NSSplitView may host a sidebar toggle button area
            if cls.contains("NSSplitViewDivider")
                || cls.contains("NSSplitViewItemToggleButton") {
                nukeView(subview)
                continue
            }
            stripSplitViewToggleViews(in: subview, depth: depth - 1)
        }
    }

    private func hideSidebarButtons(in view: NSView, action: Selector, depth: Int) {
        guard depth > 0 else { return }
        for subview in view.subviews where subview !== accessoryHost {
            if let button = subview as? NSButton,
               isSidebarToggleButton(button, action: action) {
                nukeView(subview)
                continue
            }
            // Catch NSSplitView divider/toggle views that aren't NSButton
            let cls = NSStringFromClass(type(of: subview))
            if cls.contains("SplitViewDivider")
                || cls.contains("SplitViewItemToggle")
                || cls.contains("ToolbarItemViewer")
                || cls.contains("NavigationColumnToggle") {
                nukeView(subview)
                continue
            }
            // Catch segmented controls that contain sidebar toggle segments
            if let segmented = subview as? NSSegmentedControl {
                for i in 0..<segmented.segmentCount {
                    if let label = segmented.label(forSegment: i)?.lowercased(),
                       label.contains("sidebar") {
                        nukeView(segmented)
                        break
                    }
                }
                if subview.isHidden { continue }
            }
            hideSidebarButtons(in: subview, action: action, depth: depth - 1)
        }
    }

    /// Determine if an NSButton is a native sidebar toggle injected by SwiftUI.
    private func isSidebarToggleButton(_ button: NSButton, action: Selector) -> Bool {
        if button.action == action { return true }
        // Also catch _toggleSidebar: variant used in newer macOS versions
        if let btnAction = button.action, NSStringFromSelector(btnAction).contains("toggleSidebar") {
            return true
        }
        let cls = NSStringFromClass(type(of: button)).lowercased()
        if cls.contains("sidebartoggle")
            || cls.contains("splitviewitemtoggle")
            || cls.contains("navigationsplitview")
            || cls.contains("splitviewbutton")
            || cls.contains("columntoggle") {
            return true
        }
        let accId = button.accessibilityIdentifier().lowercased()
        let accLabel = (button.accessibilityLabel() ?? "").lowercased()
        if accId.contains("sidebar") || accLabel.contains("sidebar")
            || accId.contains("toggle") || accLabel.contains("navigation") {
            return true
        }
        // Detect by image name — native sidebar toggles use sidebar.* icons or SF Symbols
        if let imageName = button.image?.name()?.lowercased(),
           (imageName.contains("sidebar") || imageName.contains("navigationsplitview")
            || imageName.contains("rectangle.lefthalf")) {
            return true
        }
        // Detect by accessibility description on the image (SF Symbols often set this)
        if let imgDesc = button.image?.accessibilityDescription?.lowercased(),
           (imgDesc.contains("sidebar") || imgDesc.contains("navigation")) {
            return true
        }
        return false
    }

    /// Aggressively remove a view so SwiftUI cannot re-show it.
    /// The periodic timer will catch any SwiftUI re-creation within 0.25s.
    private func nukeView(_ view: NSView) {
        view.isHidden = true
        view.alphaValue = 0
        view.setFrameSize(.zero)
        view.removeFromSuperview()
    }

    /// Hide any title text fields in the titlebar or content that display the app name.
    private func hideTitlebarTitleText(in view: NSView, depth: Int) {
        guard depth > 0 else { return }
        for subview in view.subviews where subview !== accessoryHost {
            if let textField = subview as? NSTextField {
                let text = textField.stringValue
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if isAppTitleText(text) {
                    textField.stringValue = ""
                    nukeView(textField)
                    continue
                }
            }
            // Catch SwiftUI-generated text views that render the window/app title
            let cls = NSStringFromClass(type(of: subview))
            if cls.contains("TitleTextField")
                || cls.contains("TitlebarTextField")
                || cls.contains("WindowTitleText") {
                nukeView(subview)
                continue
            }
            hideTitlebarTitleText(in: subview, depth: depth - 1)
        }
    }

    private func isAppTitleText(_ text: String) -> Bool {
        if text.isEmpty { return false }
        return text == "codigo"
            || text == "codigoapp"
            || text == "coderide"
            || text == "codigoide"
            || text == "coder ide"
            || text.hasPrefix("codigo —")
            || text.hasPrefix("codigo –")
            || text.hasPrefix("codigo -")
            || text.hasPrefix("codigo ")
            || text.hasPrefix("coderide ")
            || text.contains("codigo")
    }

    private func stripAutomaticSidebarToolbarItems(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }

        let removableIdentifiers: [NSToolbarItem.Identifier] = [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .init("com.apple.SwiftUI.navigationSplitView.toggleSidebar"),
            .init("com.apple.SwiftUI.splitViewSeparator-0"),
        ]

        let indices = toolbar.items.enumerated().compactMap { index, item -> Int? in
            let identifier = item.itemIdentifier
            let rawValue = identifier.rawValue
            if removableIdentifiers.contains(identifier) { return index }
            if rawValue.hasPrefix("com.apple.SwiftUI.splitViewSeparator-") { return index }
            if rawValue.contains("navigationSplitView.toggleSidebar") { return index }
            return nil
        }

        for index in indices.reversed() {
            toolbar.removeItem(at: index)
        }
    }
}
