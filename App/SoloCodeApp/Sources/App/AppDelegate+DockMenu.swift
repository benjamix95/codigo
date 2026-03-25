import AppKit

extension AppDelegate {
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let newWindowItem = NSMenuItem(
            title: "New Window",
            action: #selector(openNewWindowFromDock(_:)),
            keyEquivalent: ""
        )
        newWindowItem.target = self
        menu.addItem(newWindowItem)
        return menu
    }

    @MainActor @objc private func openNewWindowFromDock(_ sender: Any?) {
        if triggerMainMenuNewWindowAction() {
            return
        }
        // Avoid sending non-Sendable `sender` across isolation — pass nil instead
        _ = NSApplication.shared.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
    }

    @MainActor private func triggerMainMenuNewWindowAction() -> Bool {
        guard let mainMenu = NSApplication.shared.mainMenu,
              let newWindowItem = findNewWindowMenuItem(in: mainMenu),
              let action = newWindowItem.action
        else {
            return false
        }

        // sendAction con target nil: AppKit usa la responder chain per trovare il target.
        return NSApplication.shared.sendAction(action, to: nil, from: nil)
    }

    private func findNewWindowMenuItem(in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if isNewWindowMenuItem(item) {
                return item
            }
            if let submenu = item.submenu,
               let match = findNewWindowMenuItem(in: submenu) {
                return match
            }
        }
        return nil
    }

    private func isNewWindowMenuItem(_ item: NSMenuItem) -> Bool {
        item.keyEquivalent.lowercased() == "n"
            && item.keyEquivalentModifierMask.contains(.command)
            && item.action != nil
    }
}
