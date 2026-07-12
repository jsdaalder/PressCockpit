import Foundation

struct CommandRunner {
    let workspaceRoot: URL
    let appProfile: AppProfile

    func run(
        workflow: WorkflowDefinition,
        state: WorkflowParameterState,
        selection: WorkspaceItem?
    ) throws -> WorkflowRun {
        let resolver = WorkflowRegistry(workspaceRoot: workspaceRoot, appProfile: appProfile)
        let command = try resolver.resolveCommand(workflow: workflow, state: state, selection: selection)

        let runsRoot = supportDirectory().appendingPathComponent("runs", isDirectory: true)
        try FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true, attributes: nil)

        let runID = UUID().uuidString.lowercased()
        let started = isoTimestamp()
        let runDirectory = runsRoot.appendingPathComponent("\(started)-\(runID)", isDirectory: true)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true, attributes: nil)

        let stdoutURL = runDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = runDirectory.appendingPathComponent("stderr.txt")
        let manifestURL = runDirectory.appendingPathComponent("manifest.json")
        let commandURL = runDirectory.appendingPathComponent("command.txt")

        let process = Process()
        process.executableURL = try Self.resolveExecutableURL(
            for: command.executable,
            environment: ProcessInfo.processInfo.environment
        )
        process.arguments = command.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory)
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = StreamBuffer()
        let stderrBuffer = StreamBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutBuffer.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
            }
        }

        var launchError: Error?
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            launchError = error
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let stdoutText = stdoutBuffer.text
        let stderrText = stderrBuffer.text + (launchError.map { "\n\($0.localizedDescription)" } ?? "")

        try write(stdoutText, to: stdoutURL)
        try write(stderrText, to: stderrURL)
        try write(command.commandPreview + "\n", to: commandURL)

        let finish = isoTimestamp()
        let exitCode = launchError == nil ? Int(process.terminationStatus) : -1

        let manifest = WorkflowRunManifest(
            id: runID,
            workflowID: workflow.id,
            workflowLabel: workflow.label,
            startedAt: started,
            finishedAt: finish,
            exitCode: exitCode,
            commandPreview: command.commandPreview,
            workingDirectory: command.workingDirectory,
            selectionPath: selection?.path,
            stdoutPath: stdoutURL.path,
            stderrPath: stderrURL.path,
            manifestPath: manifestURL.path,
            artifactPaths: buildArtifactPaths(
                command: command,
                workspaceRoot: workspaceRoot,
                stdoutURL: stdoutURL,
                stderrURL: stderrURL,
                commandURL: commandURL
            )
        )
        try writeJSON(manifest, to: manifestURL)

        if let launchError {
            throw launchError
        }

        return WorkflowRun(
            id: runID,
            workflowID: workflow.id,
            workflowLabel: workflow.label,
            startedAt: started,
            finishedAt: finish,
            exitCode: exitCode,
            commandPreview: command.commandPreview,
            workingDirectory: command.workingDirectory,
            stdoutPath: stdoutURL.path,
            stderrPath: stderrURL.path,
            manifestPath: manifestURL.path,
            artifactPaths: manifest.artifactPaths,
            selectionPath: selection?.path
        )
    }

    private func buildArtifactPaths(
        command: ResolvedWorkflowCommand,
        workspaceRoot: URL,
        stdoutURL: URL,
        stderrURL: URL,
        commandURL: URL
    ) -> [String] {
        var paths = [stdoutURL.path, stderrURL.path, commandURL.path]

        for template in command.estimatedOutputs {
            let candidate: URL
            if template.hasPrefix("/") {
                candidate = URL(fileURLWithPath: template)
            } else {
                candidate = URL(fileURLWithPath: template, relativeTo: workspaceRoot).standardizedFileURL
            }
            if FileManager.default.fileExists(atPath: candidate.path) {
                paths.append(candidate.path)
            }
        }

        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    private func supportDirectory() -> URL {
        journalismWorkflowHubSupportDirectory()
    }

    private func write(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func isoTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: .now)
    }

    static func resolveExecutableURL(
        for executable: String,
        environment: [String: String],
        fileManager: FileManager = .default
    ) throws -> URL {
        if executable.contains("/") {
            return URL(fileURLWithPath: executable)
        }

        let pathValue = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
        let directories = pathValue.split(separator: ":").map(String.init)

        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw NSError(
            domain: "JournalismWorkflowHub.CommandRunner",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Executable not found on PATH: \(executable)"]
        )
    }
}

private final class StreamBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct WorkflowRunManifest: Codable {
    let id: String
    let workflowID: String
    let workflowLabel: String
    let startedAt: String
    let finishedAt: String
    let exitCode: Int
    let commandPreview: String
    let workingDirectory: String
    let selectionPath: String?
    let stdoutPath: String
    let stderrPath: String
    let manifestPath: String
    let artifactPaths: [String]
}
