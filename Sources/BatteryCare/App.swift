import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set only for a real quit (menu bar “退出”, ⌥⌘Q, updater, uninstall). ⌘Q / Dock quit just hide to the menu bar.
    static var reallyQuit = false

    func applicationDidFinishLaunching(_ n: Notification) {
        AppModel.shared.start()
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            if let w = n.object as? NSWindow, AppModel.isMainWindow(w) { AppModel.shared.applyDock(windowOpen: true) }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? NSWindow, AppModel.isMainWindow(w) else { return }
            DispatchQueue.main.async { AppModel.shared.applyDock() }
        }
        DispatchQueue.main.async { AppModel.shared.applyDock() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        // Allow real quits, logout/shutdown/restart, and the case where there is no menu bar icon to fall back to.
        if Self.reallyQuit || model.prefs.iconStyle == .hidden || isSystemQuit() { return .terminateNow }
        NSApp.windows.filter(AppModel.isMainWindow).forEach { $0.close() }
        model.applyDock(windowOpen: false)
        return .terminateCancel
    }

    private func isSystemQuit() -> Bool {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent,
              let reason = ev.attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue else { return false }
        return [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown]
            .map { OSType($0) }.contains(reason)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ n: Notification) { AppModel.shared.willTerminate() }
    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach { AppModel.shared.handle(url: $0) } }
}

@main
struct BatteryCareApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("电池管家", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button("隐藏到菜单栏") { _ = NSApp.delegate?.applicationShouldTerminate?(NSApp) }
                    .keyboardShortcut("q", modifiers: .command)
                Button("完全退出电池管家") { AppModel.shared.quitCompletely() }
                    .keyboardShortcut("q", modifiers: [.command, .option])
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { AppModel.shared.selection = .other; Updater.shared.check(userInitiated: true) }
            }
        }

        MenuBarExtra(isInserted: Binding(get: { model.prefs.iconStyle != .hidden },
                                         set: { if !$0 { model.prefs.iconStyle = .hidden } })) {
            MenuBarPanel().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
