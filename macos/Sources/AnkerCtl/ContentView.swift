import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(ServerController.self) private var server
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var store = WebViewStore()

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
