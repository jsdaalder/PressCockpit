import Foundation

protocol WorkspaceCataloging {
    func load() -> WorkspaceCatalog?
    func loadSnapshot() -> WorkspaceSnapshot?
    func replace(with snapshot: WorkspaceSnapshot)
}

struct WorkspaceCatalog: Codable {
    let version: Int
    let workspaceRootPath: String
    let storedAt: Date
    let snapshot: WorkspaceSnapshot
    let records: [WorkspaceCatalogRecord]
}

struct WorkspaceCatalogRecord: Codable, Hashable {
    let id: String
    let path: String
    let readmePath: String?
    let agentsPath: String?
    let section: WorkspaceSection
    let title: String
    let projectType: WorkspaceProjectType
    let lifecycleStage: String
    let activityState: ProjectActivityState?
    let workflowStage: ProjectWorkflowStage?
    let inactiveReason: ProjectInactiveReason?
    let compatibilityStatus: ProjectLifecycleStatus?
    let safetyPosture: WorkspaceSafetyPosture
    let readmeModifiedAt: Date?
    let agentsModifiedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case readmePath
        case agentsPath
        case section
        case title
        case projectType
        case lifecycleStage
        case activityState
        case workflowStage
        case inactiveReason
        case compatibilityStatus = "lifecycleStatus"
        case safetyPosture
        case readmeModifiedAt
        case agentsModifiedAt
    }
}

struct WorkspaceCatalogStore {
    let workspaceRoot: URL
    let supportDirectory: URL
    let fileManager: FileManager

    init(
        workspaceRoot: URL,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.workspaceRoot = workspaceRoot
        self.fileManager = fileManager
        self.supportDirectory = supportDirectory ?? journalismWorkflowHubSupportDirectory(fileManager: fileManager)
    }

    func load() -> WorkspaceCatalog? {
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? decoder.decode(WorkspaceCatalog.self, from: data),
              catalog.workspaceRootPath == workspaceRoot.path else {
            return nil
        }
        return catalog
    }

    func loadSnapshot() -> WorkspaceSnapshot? {
        load()?.snapshot
    }

    func replace(with snapshot: WorkspaceSnapshot) {
        let records = snapshot.items.map(makeRecord).sorted {
            if $0.section.rawValue != $1.section.rawValue {
                return $0.section.rawValue < $1.section.rawValue
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        let catalog = WorkspaceCatalog(
            version: 1,
            workspaceRootPath: workspaceRoot.path,
            storedAt: .now,
            snapshot: snapshot,
            records: records
        )

        do {
            try fileManager.createDirectory(at: catalogDirectory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(catalog)
            try data.write(to: catalogURL, options: .atomic)
        } catch {
            // Catalog persistence should not break the live workspace scan path.
        }
    }

    private var catalogDirectory: URL {
        supportDirectory.appendingPathComponent("catalog", isDirectory: true)
    }

    private var catalogURL: URL {
        catalogDirectory.appendingPathComponent("workspace_catalog.json")
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

    private func makeRecord(from item: WorkspaceItem) -> WorkspaceCatalogRecord {
        WorkspaceCatalogRecord(
            id: item.id,
            path: item.path,
            readmePath: item.readmePath,
            agentsPath: item.agentsPath,
            section: item.section,
            title: item.title,
            projectType: item.projectType,
            lifecycleStage: item.projectStateDetailLabel,
            activityState: item.activityState,
            workflowStage: item.workflowStage,
            inactiveReason: item.inactiveReason,
            compatibilityStatus: item.compatibilityStatus,
            safetyPosture: item.safetyPosture,
            readmeModifiedAt: modificationDate(for: item.readmePath),
            agentsModifiedAt: modificationDate(for: item.agentsPath)
        )
    }

    private func modificationDate(for path: String?) -> Date? {
        guard let path else { return nil }
        return (try? fileManager.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }
}

extension WorkspaceCatalogStore: WorkspaceCataloging { }
