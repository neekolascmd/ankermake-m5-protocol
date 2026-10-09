import Foundation

/// UserDefaults keys and defaults shared by the settings UI and the server controller.
enum SettingsKey {
    static let port = "serverPort"
    static let allowNetworkAccess = "allowNetworkAccess"
    static let printerIndex = "printerIndex"
    static let insecureTLS = "insecureTLS"
    static let keepRunningInMenuBar = "keepRunningInMenuBar"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            port: 4470,
            allowNetworkAccess: false,
            printerIndex: 0,
            insecureTLS: false,
            keepRunningInMenuBar: true,
        ])
    }
}

/// Snapshot of the settings that affect how the bundled server is launched.
struct ServerSettings: Equatable {
    var port: Int
    var allowNetworkAccess: Bool
    var printerIndex: Int
    var insecureTLS: Bool

    static var current: ServerSettings {
        let defaults = UserDefaults.standard
        return ServerSettings(
            port: defaults.integer(forKey: SettingsKey.port),
            allowNetworkAccess: defaults.bool(forKey: SettingsKey.allowNetworkAccess),
            printerIndex: defaults.integer(forKey: SettingsKey.printerIndex),
            insecureTLS: defaults.bool(forKey: SettingsKey.insecureTLS)
        )
    }

    var bindHost: String { allowNetworkAccess ? "0.0.0.0" : "127.0.0.1" }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }
}

enum Paths {
    /// Same directory the ankerctl CLI uses (platformdirs user_config_path), so
    /// a login done in the app is visible to the command line tool and vice versa.
    static var configDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ankerctl", isDirectory: true)
    }

    /// The bundled PyInstaller build of ankerctl. Set ANKERCTL_SERVER to use a
    /// different executable while developing (for example `swift run`).
    static var serverExecutable: URL? {
        if let override = ProcessInfo.processInfo.environment["ANKERCTL_SERVER"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("ankerctl/ankerctl")
    }
}
