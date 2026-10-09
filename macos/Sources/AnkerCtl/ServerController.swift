import Foundation
import Observation

/// Runs the bundled `ankerctl webserver` process and tracks its state.
@MainActor
@Observable
final class ServerController {
    enum State: Equatable {
        case stopped
        case starting
        case running
        /// Another ankerctl server was already listening on the configured port.
        case external
        case failed(String)

        var isAvailable: Bool { self == .running || self == .external }
    }

    private(set) var state: State = .stopped
    private(set) var logLines: [String] = []
    /// The settings the current server was started with.
    private(set) var activeSettings = ServerSettings.current
    /// Incremented every time the server becomes available, so views can reload.
    private(set) var generation = 0

    private var process: Process?
    private var partialLine = ""
    private var restartAfterExit = false
    private var readinessTask: Task<Void, Never>?

    private static let maxLogLines = 5000

    var baseURL: URL { activeSettings.baseURL }

    var statusText: String {
        switch state {
        case .stopped: return "Server stopped"
        case .starting: return "Starting server…"
        case .running: return "Running on \(activeSettings.bindHost):\(activeSettings.port)"
        case .external: return "Using existing server on port \(activeSettings.port)"
        case .failed(let reason): return "Server failed: \(reason)"
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil, state != .starting else { return }
        activeSettings = ServerSettings.current
        state = .starting
        readinessTask?.cancel()
        readinessTask = Task { await self.startChecked() }
    }

    func stop() {
        restartAfterExit = false
        readinessTask?.cancel()
        if let process, process.isRunning {
            appendLog("Stopping server…")
            state = .stopped
            process.terminate()
            scheduleForceKill(process)
        } else if state == .external || state == .starting {
            state = .stopped
        }
    }

    func restart() {
        if let process, process.isRunning {
            restartAfterExit = true
            readinessTask?.cancel()
            appendLog("Restarting server…")
            process.terminate()
            scheduleForceKill(process)
        } else {
            state = .stopped
            start()
        }
    }

    /// Restart only when a launch-relevant setting changed.
    func applySettingsIfChanged() {
        guard ServerSettings.current != activeSettings else { return }
        restart()
    }

    /// Synchronous shutdown used while the app is quitting.
    func shutdownForQuit() {
        readinessTask?.cancel()
        guard let process, process.isRunning else { return }
        process.terminationHandler = nil
        process.terminate()
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    func clearLog() {
        logLines.removeAll()
    }

    // MARK: - Private

    private func startChecked() async {
        let settings = activeSettings

        if await Self.probe(settings.baseURL) {
            appendLog("An ankerctl server is already running on port \(settings.port); using it.")
            appendLog("Settings changed in this app do not apply to that server.")
            state = .external
            generation += 1
            return
        }
        guard !Task.isCancelled else { return }
        launch(settings)
    }

    private func launch(_ settings: ServerSettings) {
        guard let executable = Paths.serverExecutable,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            state = .failed("bundled ankerctl server not found")
            appendLog("Could not find the ankerctl server executable. Rebuild the app with macos/build-app.sh.")
            return
        }

        let configDir = Paths.configDirectory
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        var arguments: [String] = []
        if settings.insecureTLS {
            arguments.append("--insecure")
        }
        arguments += [
            "--printer", String(settings.printerIndex),
            "webserver", "run",
            "--host", settings.bindHost,
            "--port", String(settings.port),
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["NO_COLOR"] = "1"
        environment["ANKERCTL_PARENT_PID"] = String(getpid())

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // python-dotenv looks for a .env file in the working directory of a
        // frozen app; keep it pointed somewhere predictable.
        process.currentDirectoryURL = configDir

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.consumeOutput(text) }
        }
        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            Task { @MainActor in self?.processExited(proc, status: status, reason: reason) }
        }

        appendLog("$ ankerctl \(arguments.joined(separator: " "))")
        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
            appendLog("Failed to launch server: \(error.localizedDescription)")
            return
        }
        self.process = process

        readinessTask = Task { await self.awaitReady(process, url: settings.baseURL) }
    }

    private func awaitReady(_ process: Process, url: URL) async {
        let deadline = Date().addingTimeInterval(60)
        while !Task.isCancelled && process.isRunning && Date() < deadline {
            if await Self.probe(url) {
                guard self.process === process else { return }
                state = .running
                generation += 1
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if !Task.isCancelled && process.isRunning && self.process === process {
            state = .failed("server did not respond within 60 seconds")
        }
    }

    private func processExited(_ proc: Process, status: Int32, reason: Process.TerminationReason) {
        guard proc === process else { return }
        flushPartialLine()
        process = nil
        readinessTask?.cancel()

        if restartAfterExit {
            restartAfterExit = false
            appendLog("Server stopped.")
            state = .stopped
            start()
            return
        }

        switch state {
        case .starting, .running:
            let detail = reason == .uncaughtSignal ? "signal \(status)" : "exit code \(status)"
            if logLines.contains(where: { $0.contains("Address already in use") }) {
                state = .failed("port \(activeSettings.port) is in use by another program")
            } else {
                state = .failed("server exited (\(detail))")
            }
            appendLog("Server exited (\(detail)).")
        default:
            appendLog("Server stopped.")
            state = .stopped
        }
    }

    private func scheduleForceKill(_ process: Process) {
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    private func consumeOutput(_ text: String) {
        partialLine += text
        var lines = partialLine.components(separatedBy: "\n")
        partialLine = lines.removeLast()
        for line in lines {
            appendLog(Self.stripANSI(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))))
        }
    }

    /// Werkzeug colors some of its own log lines regardless of NO_COLOR.
    private static func stripANSI(_ line: String) -> String {
        guard line.contains("\u{1B}") else { return line }
        return line.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }

    private func flushPartialLine() {
        if !partialLine.isEmpty {
            appendLog(Self.stripANSI(partialLine))
            partialLine = ""
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > Self.maxLogLines {
            logLines.removeFirst(logLines.count - Self.maxLogLines)
        }
    }

    /// Returns true if an ankerctl server answers on the given base URL.
    nonisolated static func probe(_ baseURL: URL) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["api"] != nil && json["server"] != nil
    }
}
