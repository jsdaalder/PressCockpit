import Foundation

protocol MaintenancePersisting {
    var storageDirectory: URL { get }
    func load() -> [MaintenanceItem]
    func replace(with items: [MaintenanceItem])
}

private struct MaintenanceCatalog: Codable {
    let version: Int
    let workspaceRootPath: String
    let storedAt: Date
    let items: [MaintenanceItem]
}

struct MaintenanceStore {
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
        self.storageDirectory = journalismWorkflowHubMaintenanceDirectory(
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )
    }

    func load() -> [MaintenanceItem] {
        guard let data = try? Data(contentsOf: storageURL),
              let catalog = try? decoder.decode(MaintenanceCatalog.self, from: data),
              catalog.workspaceRootPath == workspaceRoot.path else {
            return []
        }
        return catalog.items.sorted { $0.createdAt > $1.createdAt }
    }

    func replace(with items: [MaintenanceItem]) {
        let catalog = MaintenanceCatalog(
            version: 1,
            workspaceRootPath: workspaceRoot.path,
            storedAt: .now,
            items: items.sorted { $0.createdAt > $1.createdAt }
        )

        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(catalog)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Maintenance persistence should not block the app shell.
        }
    }

    private var storageURL: URL {
        storageDirectory.appendingPathComponent("maintenance_queue.json")
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

extension MaintenanceStore: MaintenancePersisting { }
