import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(ServerController.self) private var server
    @Environment(LocalNetworkAccess.self) private var localNetwork
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var store = WebViewStore()
    @State private var hideLocalNetworkBanner = false

    var body: some View {
        Group {
            switch server.state {
            case .running, .external:
                WebView(url: server.baseURL, generation: server.generation, store: store)
            case .starting:
                ProgressView("Starting ankerctl server…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .stopped:
                placeholder(
                    symbol: "stop.circle",
                    title: "Server stopped",
                    message: "Start the server to use the ankerctl web interface."
                )
            case .failed(let reason):
                placeholder(
                    symbol: "exclamationmark.triangle",
                    title: "The ankerctl server is not running",
                    message: reason.prefix(1).uppercased() + reason.dropFirst() + "."
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showLocalNetworkBanner {
                LocalNetworkBanner(
                    openSettings: localNetwork.openSettings,
                    dismiss: { hideLocalNetworkBanner = true }
                )
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                StatusBadge(state: server.state)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.goHome(server.baseURL)
                } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Go to the ankerctl home page")
                .disabled(!server.state.isAvailable)

                Button {
                    store.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload the page")
                .keyboardShortcut("r")
                .disabled(!server.state.isAvailable)

                Button {
                    NSWorkspace.shared.open(server.baseURL)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                .help("Open the web interface in your default browser")
                .disabled(!server.state.isAvailable)

                Button {
                    openWindow(id: WindowID.log)
                } label: {
                    Label("Server Log", systemImage: "text.alignleft")
                }
                .help("Show the server log")
            }
        }
        .onAppear { DockIcon.update(mainWindowVisible: true) }
        .onDisappear { DockIcon.update(mainWindowVisible: false) }
    }

    /// The permission only matters for the server the app starts itself.
    private var showLocalNetworkBanner: Bool {
        localNetwork.status == .blocked && !hideLocalNetworkBanner && server.state != .external
    }

    private func placeholder(symbol: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            HStack {
                Button(server.state == .stopped ? "Start Server" : "Try Again") { server.restart() }
                    .buttonStyle(.borderedProminent)
                Button("Show Log") { openWindow(id: WindowID.log) }
                Button("Settings…") { openSettings() }
            }
        }
    }
}

/// Shown while macOS blocks local network access, which the server needs to
/// find and connect to the printer.
struct LocalNetworkBanner: View {
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("ankerctl can’t reach your local network")
                    .font(.callout.weight(.semibold))
                Text("Allow local network access so ankerctl can find and connect to your printer: click Allow when macOS asks, or turn on ankerctl in System Settings ▸ Privacy & Security ▸ Local Network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Open Privacy Settings", action: openSettings)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Hide this message")
            .accessibilityLabel("Hide")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct StatusBadge: View {
    let state: ServerController.State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .running, .external: return .green
        case .starting: return .yellow
        case .stopped: return .gray
        case .failed: return .red
        }
    }

    private var label: String {
        switch state {
        case .running: return "Server running"
        case .external: return "External server"
        case .starting: return "Starting"
        case .stopped: return "Stopped"
        case .failed: return "Server error"
        }
    }
}
