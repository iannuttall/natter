import AppKit

@MainActor
enum ApplicationMenu {
    static func install() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private static func appMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem()
        let menu = NSMenu(title: AppInfo.displayName)
        rootItem.submenu = menu

        menu.addItem(NSMenuItem(
            title: "About \(AppInfo.displayName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Hide \(AppInfo.displayName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))

        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit \(AppInfo.displayName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return rootItem
    }

    private static func editMenuItem() -> NSMenuItem {
        let rootItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        rootItem.submenu = menu

        menu.addItem(NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))

        let redo = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        menu.addItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        menu.addItem(NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        menu.addItem(NSMenuItem(
            title: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))

        return rootItem
    }
}
