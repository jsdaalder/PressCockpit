import Foundation

protocol CapturePersisting {
    var storageDirectory: URL { get }
    func load() -> CaptureCatalog?
    func loadRecords() -> [CaptureRecord]?
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

    func load() -> CaptureCatalog? {
        guard let data = try? Data(contentsOf: storageURL),
              let catalog = try? decoder.decode(CaptureCatalog.self, from: data),
              catalog.workspaceRootPath == workspaceRoot.path else {
            return nil
        }
        return catalog
    }

    func loadRecords() -> [CaptureRecord]? {
        load()?.records
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
}

extension CaptureStore: CapturePersisting { }
