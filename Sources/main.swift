import AppKit
import SwiftUI
import Foundation
import Darwin

umask(0o077)
let arguments = CommandLine.arguments

if arguments.contains("--self-test") {
    exit(runSelfTests())
}
if arguments.contains("--check-json") {
    do {
        let result = try SessionEngine(paths: LocalPaths.discover()).inspect()
        let status = result.state == .existingSession ? "desktop_session_exists" : result.state == .ready ? "ready_for_import" : "quit_desktop_first"
        let data = try JSONSerialization.data(withJSONObject: ["status": status, "desktop_version": result.version], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self)); exit(0)
    } catch {
        let failure = readableFailure(error)
        let data = try! JSONSerialization.data(withJSONObject: ["status": "stopped", "code": failure.code, "message": failure.detail], options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self)); exit(1)
    }
}

let application = NSApplication.shared

if let index = arguments.firstIndex(of: "--render-preview"), arguments.count > index + 1 {
    application.setActivationPolicy(.prohibited)
    let sceneIndex = arguments.firstIndex(of: "--scene")
    let scene = sceneIndex.flatMap { arguments.count > $0 + 1 ? arguments[$0 + 1] : nil } ?? "welcome"
    let appearance = NSAppearance(named: arguments.contains("--dark") ? .darkAqua : .aqua)
    application.appearance = appearance
    let model = HelperModel.demonstration(scene)
    let window: NSWindow
    if let copy = ConfirmCopy.demonstration(scene) {
        // The app shows these as standard alerts; lay one out without running it.
        let alert = NSAlert()
        alert.messageText = copy.title; alert.informativeText = copy.message
        alert.addButton(withTitle: copy.action); alert.addButton(withTitle: String(localized: "Cancel"))
        alert.layout()
        window = alert.window
    } else if let sheet = model.sheet {
        let view = NSHostingView(rootView: HelperSheetView(sheet: sheet, model: model))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
    } else {
        window = makeMainWindow(model: model)
    }
    window.appearance = appearance
    window.orderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    // Capture the window frame too, so the title bar buttons appear as they do in the app.
    guard let content = window.contentView else { print("The view could not be rendered."); exit(1) }
    let captured = content.superview ?? content
    captured.layoutSubtreeIfNeeded()
    // --scale 2 renders at Retina resolution regardless of the current display.
    let scale = arguments.firstIndex(of: "--scale").flatMap { arguments.count > $0 + 1 ? Double(arguments[$0 + 1]) : nil } ?? 1
    let bounds = captured.bounds
    if scale >= 1, scale <= 4, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
        bitmap.size = bounds.size
        captured.cacheDisplay(in: bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            do { try png.write(to: URL(fileURLWithPath: arguments[index + 1]), options: .withoutOverwriting); print("UI preview rendered with demonstration data.") }
            catch { print("The preview could not be saved."); exit(1) }
        } else { print("No preview image was produced."); exit(1) }
    } else { print("The view could not be rendered."); exit(1) }
    window.orderOut(nil)
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var window: NSWindow?
    let model = HelperModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        let window = makeMainWindow(model: model)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ClaudeSignInHelper.MainWindow")
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.makeKeyAndOrderFront(nil); return true
    }

    private func installMenus() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); let submenu = NSMenu(title: title)
            item.submenu = submenu; menu.addItem(item); return submenu
        }
        let appMenu = submenu("")
        appMenu.addItem(withTitle: String(localized: "About Claude Sign-In Helper"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        // Language: tag -1 follows the system; other tags index AppLanguage.choices.
        let languageMenu = NSMenu(title: String(localized: "Language"))
        languageMenu.addItem(withTitle: String(localized: "System Default"), action: #selector(chooseLanguage(_:)), keyEquivalent: "").tag = -1
        languageMenu.addItem(.separator())
        for (index, choice) in AppLanguage.choices.enumerated() {
            languageMenu.addItem(withTitle: choice.name, action: #selector(chooseLanguage(_:)), keyEquivalent: "").tag = index
        }
        languageMenu.items.forEach { $0.target = self }
        appMenu.addItem(withTitle: String(localized: "Language"), action: nil, keyEquivalent: "").submenu = languageMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide Claude Sign-In Helper"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Claude Sign-In Helper"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(String(localized: "File"))
        fileMenu.addItem(withTitle: String(localized: "Backups…"), action: #selector(showBackups(_:)), keyEquivalent: "b").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let windowMenu = submenu(String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        let helpMenu = submenu(String(localized: "Help"))
        helpMenu.addItem(withTitle: String(localized: "How It Works"), action: #selector(showHelp(_:)), keyEquivalent: "?").target = self
        helpMenu.addItem(withTitle: String(localized: "Anthropic Sign-In Support"), action: #selector(openSupportArticle(_:)), keyEquivalent: "").target = self

        NSApp.mainMenu = menu; NSApp.windowsMenu = windowMenu; NSApp.helpMenu = helpMenu
    }

    @objc private func showBackups(_ sender: Any?) { window?.makeKeyAndOrderFront(nil); model.present(.backups) }
    @objc private func showHelp(_ sender: Any?) { window?.makeKeyAndOrderFront(nil); model.present(.help) }
    @objc private func openSupportArticle(_ sender: Any?) { model.openSupport() }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        let code = AppLanguage.choices.indices.contains(sender.tag) ? AppLanguage.choices[sender.tag].code : nil
        guard !AppLanguage.isSelected(code) else { return }
        AppLanguage.select(code)
        guard AppLanguage.resolved(code) != AppLanguage.current else { return }
        // The language is fixed while the app runs, so offer to reopen it now.
        let alert = NSAlert()
        alert.messageText = String(localized: "Restart to change the language?")
        alert.informativeText = String(localized: "Claude Sign-In Helper will quit and reopen in the language you chose.")
        alert.addButton(withTitle: String(localized: "Restart Now"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn { AppLanguage.relaunch() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showBackups(_:)):
            return !model.busy
        case #selector(chooseLanguage(_:)):
            let code = AppLanguage.choices.indices.contains(menuItem.tag) ? AppLanguage.choices[menuItem.tag].code : nil
            menuItem.state = AppLanguage.isSelected(code) ? .on : .off
            return !model.busy // A restart must never interrupt an import or restore.
        default:
            return true
        }
    }
}

let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
