import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        AppModel.shared.applyDock()
        AppModel.shared.start()
    }
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
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra(isInserted: Binding(get: { model.prefs.iconStyle != .hidden },
                                         set: { if !$0 { model.prefs.iconStyle = .hidden; model.prefs.showDock = true } })) {
            MenuBarPanel().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
