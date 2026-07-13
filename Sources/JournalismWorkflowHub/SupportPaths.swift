import Foundation

func journalismWorkflowHubSupportDirectory(
    fileManager: FileManager = .default,
    processInfo: ProcessInfo = .processInfo
) -> URL {
    if isRunningJournalismWorkflowHubTests(processInfo: processInfo) {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("JournalismWorkflowHubTests", isDirectory: true)
            .appendingPathComponent(String(processInfo.processIdentifier), isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JournalismWorkflowHub", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

private func isRunningJournalismWorkflowHubTests(processInfo: ProcessInfo) -> Bool {
    processInfo.environment["XCTestConfigurationFilePath"] != nil
        || Bundle.allBundles.contains(where: { $0.bundlePath.hasSuffix(".xctest") })
}

func journalismWorkflowHubCaptureDirectory(
    supportDirectory: URL? = nil,
    fileManager: FileManager = .default
) -> URL {
    let url = (supportDirectory ?? journalismWorkflowHubSupportDirectory(fileManager: fileManager))
        .appendingPathComponent("capture", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

func journalismWorkflowHubMaintenanceDirectory(
    supportDirectory: URL? = nil,
    fileManager: FileManager = .default
) -> URL {
    let url = (supportDirectory ?? journalismWorkflowHubSupportDirectory(fileManager: fileManager))
        .appendingPathComponent("maintenance", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

func journalismWorkflowHubWorkflowBackupDirectory(
    supportDirectory: URL? = nil,
    fileManager: FileManager = .default
) -> URL {
    let url = (supportDirectory ?? journalismWorkflowHubSupportDirectory(fileManager: fileManager))
        .appendingPathComponent("workflow_backups", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

func journalismWorkflowHubLogsDirectory(
    supportDirectory: URL? = nil,
    fileManager: FileManager = .default
) -> URL {
    let url = (supportDirectory ?? journalismWorkflowHubSupportDirectory(fileManager: fileManager))
        .appendingPathComponent("logs", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

@discardableResult
func createWorkflowWriteBackups(
    paths: [String],
    workspaceRoot: URL,
    supportDirectory: URL? = nil,
    fileManager: FileManager = .default,
    now: Date = .now
) throws -> [String] {
    let backupRoot = journalismWorkflowHubWorkflowBackupDirectory(
        supportDirectory: supportDirectory,
        fileManager: fileManager
    ).appendingPathComponent(workflowBackupTimestamp(now), isDirectory: true)
    try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true, attributes: nil)

    let workspaceRootPath = workspaceRoot.standardizedFileURL.path
    var createdBackups: [String] = []
    var seenPaths = Set<String>()

    for rawPath in paths {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        let sourceURL = URL(fileURLWithPath: trimmed).standardizedFileURL
        guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
        guard seenPaths.insert(sourceURL.path).inserted else { continue }

        let destinationURL = backupRoot.appendingPathComponent(
            workflowBackupRelativePath(for: sourceURL, workspaceRootPath: workspaceRootPath),
            isDirectory: false
        )
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        createdBackups.append(destinationURL.path)
    }

    return createdBackups
}

private func workflowBackupTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd_HHmmss"
    return formatter.string(from: date)
}

private func workflowBackupRelativePath(for sourceURL: URL, workspaceRootPath: String) -> String {
    let sourcePath = sourceURL.path
    if sourcePath.hasPrefix(workspaceRootPath + "/") {
        return String(sourcePath.dropFirst(workspaceRootPath.count + 1))
    }

    let sanitized = sourcePath
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "/", with: "_")
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return "external/\(sanitized.isEmpty ? sourceURL.lastPathComponent : sanitized)"
}

func bundledDemoWorkspaceRoot(bundle: Bundle = .module, fileManager: FileManager = .default) -> URL? {
    guard let resourceRoot = bundle.resourceURL else {
        return nil
    }

    let candidate = resourceRoot.appendingPathComponent("DemoWorkspace", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return nil
    }
    return candidate
}

func bundledKnowledgeOpsRoot(bundle: Bundle = .module, fileManager: FileManager = .default) -> URL? {
    guard let resourceRoot = bundle.resourceURL else {
        return nil
    }

    let candidate = resourceRoot.appendingPathComponent("knowledge_ops", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return nil
    }
    return candidate
}

func bundledKnowledgeOpsScriptsRoot(bundle: Bundle = .module, fileManager: FileManager = .default) -> URL? {
    guard let knowledgeOpsRoot = bundledKnowledgeOpsRoot(bundle: bundle, fileManager: fileManager) else {
        return nil
    }

    let candidate = knowledgeOpsRoot.appendingPathComponent("scripts", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return nil
    }
    return candidate
}

func bundledKnowledgeOpsScriptPath(
    _ name: String,
    bundle: Bundle = .module,
    fileManager: FileManager = .default
) -> String? {
    guard let scriptsRoot = bundledKnowledgeOpsScriptsRoot(bundle: bundle, fileManager: fileManager) else {
        return nil
    }

    let candidate = scriptsRoot.appendingPathComponent(name)
    guard fileManager.fileExists(atPath: candidate.path) else {
        return nil
    }
    return candidate.path
}
