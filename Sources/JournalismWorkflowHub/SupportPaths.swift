import Foundation

func journalismWorkflowHubSupportDirectory(fileManager: FileManager = .default) -> URL {
    let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JournalismWorkflowHub", isDirectory: true)
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
