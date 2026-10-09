import AppKit
import Observation
import UniformTypeIdentifiers

/// Sends G-code files to the printer through the server's OctoPrint-compatible
/// upload endpoint (the same one PrusaSlicer uses).
@MainActor
@Observable
final class PrintUploader {
    private let server: ServerController
    private(set) var isUploading = false

    static let gcodeExtensions = ["gcode", "gco", "g"]

    init(server: ServerController) {
        self.server = server
    }

    func choosePrintFile() {
        let panel = NSOpenPanel()
        panel.title = "Print G-code File"
        panel.prompt = "Print"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.gcodeExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        confirmAndPrint(url)
    }

    func confirmAndPrint(_ url: URL) {
        NSApp.activate()

        guard Self.gcodeExtensions.contains(url.pathExtension.lowercased()) else {
            showAlert(title: "Not a G-code file",
                      message: "“\(url.lastPathComponent)” can't be printed. Slice your model first and choose the exported .gcode file.")
            return
        }
        guard server.state.isAvailable else {
            showAlert(title: "Server not running",
                      message: "Start the ankerctl server before sending a print job.")
            return
        }
        guard !isUploading else {
            showAlert(title: "Upload in progress",
                      message: "Wait for the current print job to finish uploading.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Print “\(url.lastPathComponent)”?"
        alert.informativeText = "The file is sent to the printer and the print starts immediately. "
            + "Make sure the build plate is clear. The printer only stores one uploaded file, "
            + "so any previously uploaded file is replaced."
        alert.addButton(withTitle: "Print")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { await upload(url) }
    }

    private func upload(_ fileURL: URL) async {
        isUploading = true
        defer { isUploading = false }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            showAlert(title: "Could not read file", message: error.localizedDescription)
            return
        }

        let boundary = "ankerctl-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"print\"\r\n\r\ntrue\r\n")
        append("--\(boundary)\r\n")
        let filename = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: server.baseURL.appendingPathComponent("api/files/local"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15 * 60
        // The server records the part before "/" as the job's user name.
        request.setValue("ankerctl-macos/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        do {
            let (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                showAlert(title: "Print started",
                          message: "“\(fileURL.lastPathComponent)” was sent to the printer.",
                          style: .informational)
            } else {
                showAlert(title: "Print failed",
                          message: Self.errorMessage(from: responseData, status: status))
            }
        } catch {
            showAlert(title: "Print failed", message: error.localizedDescription)
        }
    }

    /// Flask's abort() responses are small HTML pages; pull the readable text out.
    private static func errorMessage(from data: Data, status: Int) -> String {
        let html = String(decoding: data, as: UTF8.self)
        let text = html
            .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if status == 500 {
            return "The server could not send the file. Check that you are logged in and the printer is online. "
                + "See the server log for details."
        }
        return text.isEmpty ? "The server returned HTTP \(status)." : text
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
