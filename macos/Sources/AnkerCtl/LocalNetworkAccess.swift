import AppKit
import Darwin
import Observation

/// Tracks whether macOS lets ankerctl reach devices on the local network.
///
/// Since macOS 15, apps need the user's permission to access the local network
/// (System Settings ▸ Privacy & Security ▸ Local Network). The bundled server
/// runs as a child of the app and uses the app's permission; without it, the
/// server's search for the printer fails with "No route to host".
///
/// The app broadcasts a printer search at launch, so macOS asks for permission
/// right away instead of the first time the server looks for the printer.
/// macOS has no API to read the permission, so the broadcast is repeated until
/// it goes through.
@MainActor
@Observable
final class LocalNetworkAccess {
    enum Status {
        case unknown
        case allowed
        /// macOS blocked the broadcast: the permission prompt is still open,
        /// or access was denied.
        case blocked
    }

    private(set) var status: Status = .unknown
    private var probeTask: Task<Void, Never>?

    private static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!

    func start() {
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                let result = await Self.sendSearchBroadcast()
                guard let self else { return }
                self.status = result
                if result == .allowed {
                    break
                }
                // Check again soon after the user answers the prompt or
                // changes the setting; retry slowly while there is no network.
                try? await Task.sleep(for: .seconds(result == .blocked ? 2 : 10))
            }
            self?.probeTask = nil
        }
    }

    func openSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    /// Broadcasts the PPPP LAN search packet that ankerctl uses to find printers.
    private nonisolated static func sendSearchBroadcast() async -> Status {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return .unknown }
        defer { close(fd) }

        var enable: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            return .unknown
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(32108).bigEndian
        address.sin_addr = in_addr(s_addr: in_addr_t.max) // 255.255.255.255

        let packet: [UInt8] = [0xF1, 0x30, 0x00, 0x00] // LAN_SEARCH
        let sent = packet.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent >= 0 {
            return .allowed
        }
        switch errno {
        case EHOSTUNREACH, EPERM:
            return .blocked
        default:
            // For example, not connected to any network.
            return .unknown
        }
    }
}
