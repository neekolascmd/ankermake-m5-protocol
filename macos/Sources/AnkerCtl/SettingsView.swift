import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(ServerController.self) private var server

    @AppStorage(SettingsKey.port) private var port = 4470
    @AppStorage(SettingsKey.allowNetworkAccess) private var allowNetworkAccess = false
    @AppStorage(SettingsKey.printerIndex) private var printerIndex = 0
    @AppStorage(SettingsKey.insecureTLS) private var insecureTLS = false
    @AppStorage(SettingsKey.keepRunningInMenuBar) private var keepRunningInMenuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    private var pendingRestart: Bool {
        server.state != .external && ServerSettings.current != server.activeSettings
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Port", value: $port, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                Toggle("Allow other devices on the network to connect", isOn: $allowNetworkAccess)
                Text("Slicers on this Mac can send prints to http://127.0.0.1:\(String(port)). "
                     + "Enable network access to use ankerctl from other computers; anyone on your network "
                     + "can then control the printer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Stepper("Printer number: \(printerIndex)", value: $printerIndex, in: 0...31)
                Toggle("Disable TLS certificate validation (insecure)", isOn: $insecureTLS)
                HStack {
                    if server.state == .external {
                        Text("Another ankerctl server is using this port.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if pendingRestart {
                        Text("Restart the server to apply changes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply and Restart Server") { server.restart() }
                        .disabled(!pendingRestart || !(1...65535).contains(port))
                }
            }

            Section("App") {
                Toggle("Keep running in the menu bar when the window is closed", isOn: $keepRunningInMenuBar)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                LabeledContent("Configuration") {
                    Button("Show in Finder") { NSWorkspace.shared.open(Paths.configDirectory) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
