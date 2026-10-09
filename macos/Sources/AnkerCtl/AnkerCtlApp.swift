import AppKit
import SwiftUI

@main
struct AnkerCtlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("ankerctl", id: WindowID.main) {
            ContentView()
                .environment(appDelegate.server)
                .environment(appDelegate.uploader)
                .environment(appDelegate.localNetwork)
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            AppCommands(server: appDelegate.server, uploader: appDelegate.uploader)
        }

        Window("Server Log", id: WindowID.log) {
            LogView()
                .environment(appDelegate.server)
        }
        .defaultSize(width: 760, height: 480)

        Settings {
            SettingsView()
                .environment(appDelegate.server)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.server)
                .environment(appDelegate.uploader)
        } label: {
            Image(systemName: appDelegate.server.state.isAvailable ? "printer.fill" : "printer")
        }
    }
}

enum WindowID {
    static let main = "main"
    static let log = "log"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let server: ServerController
    let uploader: PrintUploader
    let localNetwork = LocalNetworkAccess()

    override init() {
        SettingsKey.registerDefaults()
        let server = ServerController()
        self.server = server
        self.uploader = PrintUploader(server: server)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ask for local network access before the server needs it to find the printer.
        localNetwork.start()
        server.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsKey.keepRunningInMenuBar)
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.shutdownForQuit()
    }

    /// G-code files opened from Finder or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            uploader.confirmAndPrint(url)
        }
    }
}

/// Shows or hides the Dock icon depending on whether the main window is open.
enum DockIcon {
    @MainActor
    static func update(mainWindowVisible: Bool) {
        if mainWindowVisible {
            NSApp.setActivationPolicy(.regular)
        } else if UserDefaults.standard.bool(forKey: SettingsKey.keepRunningInMenuBar) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct AppCommands: Commands {
    let server: ServerController
    let uploader: PrintUploader
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Print G-code File…") { uploader.choosePrintFile() }
                .keyboardShortcut("o")
                .disabled(!server.state.isAvailable)
        }
        CommandMenu("Server") {
            Button("Restart Server") { server.restart() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Stop Server") { server.stop() }
                .disabled(server.state != .running)
            Divider()
            Button("Open in Browser") { NSWorkspace.shared.open(server.baseURL) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!server.state.isAvailable)
            Button("Show Server Log") { openWindow(id: WindowID.log) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Open Configuration Folder") { NSWorkspace.shared.open(Paths.configDirectory) }
        }
    }
}

struct MenuBarContent: View {
    @Environment(ServerController.self) private var server
    @Environment(PrintUploader.self) private var uploader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(server.statusText)
        Divider()
        Button("Open ankerctl") {
            openWindow(id: WindowID.main)
            NSApp.activate()
        }
        Button("Open in Browser") { NSWorkspace.shared.open(server.baseURL) }
            .disabled(!server.state.isAvailable)
        Button("Print G-code File…") {
            NSApp.activate()
            uploader.choosePrintFile()
        }
        .disabled(!server.state.isAvailable)
        Divider()
        if server.state == .stopped {
            Button("Start Server") { server.start() }
        } else {
            Button("Restart Server") { server.restart() }
        }
        Button("Show Server Log") {
            openWindow(id: WindowID.log)
            NSApp.activate()
        }
        Button("Open Configuration Folder") { NSWorkspace.shared.open(Paths.configDirectory) }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit ankerctl") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
