import AppKit
import SwiftUI

struct LogView: View {
    @Environment(ServerController.self) private var server
    @State private var followTail = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(server.logLines.enumerated()), id: \.offset) { index, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(8)
            }
            .onChange(of: server.logLines.count) { _, count in
                if followTail && count > 0 {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = server.logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $followTail) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .help("Scroll to new log lines automatically")
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(server.logLines.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help("Copy the whole log. It can contain your email address and printer details.")
                Button {
                    server.clearLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear the log")
            }
        }
        .navigationTitle("Server Log")
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("[E]") || line.hasPrefix("[!]") || line.hasPrefix("Traceback") {
            return .red
        }
        if line.hasPrefix("[W]") {
            return .orange
        }
        return .primary
    }
}
