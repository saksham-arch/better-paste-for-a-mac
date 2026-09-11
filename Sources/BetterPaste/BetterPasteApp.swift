import AppKit
import Carbon
import SwiftUI

@main
struct BetterPasteApp {
    private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardHistoryStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private lazy var pasteController = PasteController(store: store)
    private lazy var pickerController = PickerWindowController(
        store: store,
        pasteController: pasteController
    )
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var controlPanelWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ConfigManager.shared.ensureConfigExists()
        store.reloadLimit()
        monitor.start()
        installMenuBar()
        installEditingMenu()
        registerHotKey()

        PasteController.requestAccessibilityIfNeeded()
    }

    private func installMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Better Paste")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Better Paste", action: #selector(showControlPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Clipboard Picker", action: #selector(showPicker), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Better Paste", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func registerHotKey() {
        hotKeyManager = HotKeyManager(config: ConfigManager.shared.config) { [weak self] in
            self?.showPicker()
        }
        reportHotKeyStatus(hotKeyManager?.register() ?? OSStatus(eventInternalErr))
    }

    private func installEditingMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [
            ("Undo", "undo:", "z"),
            ("Cut", "cut:", "x"),
            ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func showPicker() {
        store.reloadLimit()
        pickerController.show()
    }

    @objc private func showControlPanel() {
        let view = ControlPanelView(
            store: store,
            config: ConfigManager.shared.config,
            onShowPicker: { [weak self] in self?.showPicker() },
            onClearHistory: { [weak self] in self?.clearHistory() },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onSaveConfig: { [weak self] newConfig in
                var config = ConfigManager.shared.config
                config.visibleItemCount = newConfig.visibleItemCount
                config.mergeDuplicates = newConfig.mergeDuplicates
                ConfigManager.shared.save(config)
                self?.store.reloadLimit()
                self?.hotKeyManager?.unregister()
                self?.hotKeyManager = HotKeyManager(config: config) { [weak self] in
                    self?.showPicker()
                }
                self?.reportHotKeyStatus(self?.hotKeyManager?.register() ?? OSStatus(eventInternalErr))
            }
        )

        if controlPanelWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 430),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Better Paste"
            window.center()
            window.backgroundColor = .clear
            window.isOpaque = false
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            controlPanelWindow = window
        }

        controlPanelWindow?.contentView = NSHostingView(rootView: view)
        controlPanelWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func showSettings() {
        let view = SettingsView(config: ConfigManager.shared.config) { [weak self] newConfig in
            ConfigManager.shared.save(newConfig)
            self?.store.reloadLimit()
            self?.hotKeyManager?.unregister()
            self?.hotKeyManager = HotKeyManager(config: newConfig) { [weak self] in
                self?.showPicker()
            }
            self?.reportHotKeyStatus(self?.hotKeyManager?.register() ?? OSStatus(eventInternalErr))
        }

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Better Paste Settings"
            window.center()
            window.backgroundColor = .clear
            window.isOpaque = false
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.contentView = NSHostingView(rootView: view)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func clearHistory() {
        store.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func reportHotKeyStatus(_ status: OSStatus) {
        guard status != noErr else { return }

        let alert = NSAlert()
        alert.messageText = "Could not register the keyboard shortcut"
        alert.informativeText = "Another app may already use this shortcut. Choose a different shortcut in Settings. Error: \(status)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension AppConfig {
    var shortcutDescription: String {
        let modifiers = pasteShortcut.modifiers
            .map { modifier in
                switch modifier.lowercased() {
                case "command", "cmd": return "Command"
                case "control", "ctrl": return "Control"
                case "option", "alt": return "Option"
                case "shift": return "Shift"
                default: return modifier.capitalized
                }
            }
            .joined(separator: " + ")
        let key = pasteShortcut.key.uppercased()
        return modifiers.isEmpty ? key : "\(modifiers) + \(key)"
    }
}
