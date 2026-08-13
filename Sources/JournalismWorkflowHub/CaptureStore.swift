import Foundation

enum CaptureCatalogLoadResult {
    case loaded(CaptureCatalog)
    case missing
    case unreadable
    case workspaceMismatch(CaptureCatalog)
}

protocol CapturePersisting {
    var storageDirectory: URL { get }
    func loadCatalog() -> CaptureCatalogLoadResult
    func load() -> CaptureCatalog?
    func loadRecords() -> [CaptureRecord]?
    func recoverRecordsFromStorage(excluding existingRecordIDs: Set<String>) -> [CaptureRecord]
    func replace(with records: [CaptureRecord])
}

struct CaptureCatalog: Codable, Hashable {
    let version: Int
    let workspaceRootPath: String
    let storedAt: Date
    let records: [CaptureRecord]
}

struct CaptureStore {
    let workspaceRoot: URL
    let storageDirectory: URL
    let fileManager: FileManager

    init(
        workspaceRoot: URL,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.workspaceRoot = workspaceRoot
        self.fileManager = fileManager
        self.storageDirectory = journalismWorkflowHubCaptureDirectory(
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
    }

    func loadCatalog() -> CaptureCatalogLoadResult {
        guard let data = try? Data(contentsOf: storageURL) else {
            return .missing
        }

        guard let catalog = try? decoder.decode(CaptureCatalog.self, from: data) else {
            return .unreadable
        }

        guard catalog.workspaceRootPath == workspaceRoot.path else {
            return .workspaceMismatch(catalog)
        }

        return .loaded(catalog)
    }

    func load() -> CaptureCatalog? {
        guard case .loaded(let catalog) = loadCatalog() else { return nil }
        return catalog
    }

    func loadRecords() -> [CaptureRecord]? {
        load()?.records
    }

    func recoverRecordsFromStorage(excluding existingRecordIDs: Set<String> = []) -> [CaptureRecord] {
        let itemsDirectory = storageDirectory.appendingPathComponent("items", isDirectory: true)
        let requestedKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        let hintRecordsByID = recoveryHintRecordsByID()

        guard let recordDirectories = try? fileManager.contentsOfDirectory(
            at: itemsDirectory,
            includingPropertiesForKeys: Array(requestedKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var recoveredRecords: [CaptureRecord] = []

        for recordDirectory in recordDirectories {
            let recordID = recordDirectory.lastPathComponent
            guard !existingRecordIDs.contains(recordID) else { continue }

            let hintRecord = hintRecordsByID[recordID]
            guard let importedURL = recoveredImportedURL(in: recordDirectory, hintRecord: hintRecord) else { continue }
            let resourceValues = try? importedURL.resourceValues(forKeys: requestedKeys)
            let directoryValues = try? recordDirectory.resourceValues(forKeys: requestedKeys)
            let isDirectory = resourceValues?.isDirectory == true
            let recoveredCreationDate = resourceValues?.creationDate
            let recoveredModificationDate = resourceValues?.contentModificationDate
            let directoryCreationDate = directoryValues?.creationDate
            let directoryModificationDate = directoryValues?.contentModificationDate
            let capturedAt = hintRecord?.capturedAt
                ?? recoveredCreationDate
                ?? recoveredModificationDate
                ?? directoryCreationDate
                ?? directoryModificationDate
                ?? .now
            let displayName = hintRecord?.displayName ?? recoveredDisplayName(for: importedURL, isDirectory: isDirectory)
            let captureType = hintRecord?.captureType ?? (isDirectory ? .folder : recoveredFileType(for: importedURL))

            recoveredRecords.append(CaptureRecord(
                id: recordID,
                displayName: displayName,
                originalSourcePath: hintRecord?.originalSourcePath,
                importedStoragePath: importedURL.path,
                capturedAt: capturedAt,
                captureType: captureType,
                state: .needsReview,
                failureDescription: "Recovered from capture storage after stored metadata was unavailable.",
                userNote: hintRecord?.userNote,
                assignedTargetPath: nil,
                assignedAt: nil,
                assignedDestinationPath: nil
            ))
        }

        return recoveredRecords.sorted { $0.capturedAt > $1.capturedAt }
    }

    func replace(with records: [CaptureRecord]) {
        let catalog = CaptureCatalog(
            version: 1,
            workspaceRootPath: workspaceRoot.path,
            storedAt: .now,
            records: records
        )

        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(catalog)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Capture persistence should not block the app shell.
        }
    }

    private var storageURL: URL {
        storageDirectory.appendingPathComponent("capture_catalog.json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func recoveryHintRecordsByID() -> [String: CaptureRecord] {
        switch loadCatalog() {
        case .loaded(let catalog), .workspaceMismatch(let catalog):
            return Dictionary(uniqueKeysWithValues: catalog.records.map { ($0.id, $0) })
        case .missing, .unreadable:
            return [:]
        }
    }

    private func recoveredImportedURL(in recordDirectory: URL, hintRecord: CaptureRecord?) -> URL? {
        guard let children = try? fileManager.contentsOfDirectory(
            at: recordDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        if let importedStoragePath = hintRecord?.importedStoragePath {
            let expectedName = URL(fileURLWithPath: importedStoragePath).lastPathComponent
            if let matchingChild = children.first(where: { $0.lastPathComponent == expectedName }) {
                return matchingChild
            }
        }

        if let firstDirectory = children.first(where: {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) {
            return firstDirectory
        }

        return children.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    private func recoveredDisplayName(for importedURL: URL, isDirectory: Bool) -> String {
        if isDirectory {
            return importedURL.lastPathComponent
        }

        return importedURL.lastPathComponent
    }

    private func recoveredFileType(for importedURL: URL) -> CaptureRecordType {
        if importedURL.pathExtension.lowercased() == "md" {
            return .note
        }
        return .file
    }
}

extension CaptureStore: CapturePersisting { }
