import Foundation

func journalismWorkflowHubSupportDirectory(fileManager: FileManager = .default) -> URL {
    let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JournalismWorkflowHub", isDirectory: true)
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
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
