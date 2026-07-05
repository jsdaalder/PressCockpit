import Foundation

enum WorkspaceSection: String, Codable, CaseIterable {
    case projects
    case areas
    case resources
    case archives

    var label: String {
        switch self {
        case .projects: return "Projects"
        case .areas: return "Areas"
        case .resources: return "Resources"
        case .archives: return "Archives"
        }
    }
}

enum WorkspaceProjectType: String, Codable, Hashable {
    case journalism
    case dataJournalism
    case tooling
    case area
    case resource
    case archive
    case general

    var label: String {
        switch self {
        case .journalism: return "Journalism"
        case .dataJournalism: return "Data journalism"
        case .tooling: return "Tooling"
        case .area: return "Area"
        case .resource: return "Resource"
        case .archive: return "Archive"
        case .general: return "General"
        }
    }
}

enum WorkspaceSafetyPosture: String, Codable, Hashable {
    case publishable
    case internalOnly
    case localSensitive
    case archival

    var label: String {
        switch self {
        case .publishable: return "Publishable workflow"
        case .internalOnly: return "Internal workspace"
        case .localSensitive: return "Local-only / privacy check"
        case .archival: return "Archive reference"
        }
    }
}

enum SidebarSelection: Hashable {
    case overview
    case planCenter
    case workspace(String)
    case workflow(String)
    case publication
    case run(String)
}

struct WorkspaceItem: Identifiable, Hashable {
    let id: String
    let section: WorkspaceSection
    let path: String
    let readmePath: String?
    let agentsPath: String?
    let title: String
    let summary: String
    let agentsSummary: String
    let frontmatter: [String: String]
    let projectType: WorkspaceProjectType
    let lifecycleStage: String
    let safetyPosture: WorkspaceSafetyPosture
    let directFileCount: Int
    let directFolderCount: Int
    let markdownFiles: Int
    let pdfFiles: Int
    let gdocFiles: Int
    let csvFiles: Int
    let xlsxFiles: Int

    var url: URL { URL(fileURLWithPath: path) }
    var readmeURL: URL? { readmePath.map(URL.init(fileURLWithPath:)) }
    var agentsURL: URL? { agentsPath.map(URL.init(fileURLWithPath:)) }

    var subtitle: String {
        if !summary.isEmpty {
            return summary
        }
        let bits = [
            directFileCount > 0 ? "\(directFileCount) files" : nil,
            markdownFiles > 0 ? "\(markdownFiles) markdown" : nil,
            pdfFiles > 0 ? "\(pdfFiles) PDFs" : nil,
            gdocFiles > 0 ? "\(gdocFiles) Google Docs" : nil,
        ].compactMap { $0 }
        return bits.joined(separator: " • ")
    }

    var workspaceSummary: String {
        let bits = [
            projectType.label,
            lifecycleStage.isEmpty ? nil : lifecycleStage,
            agentsSummary.isEmpty ? nil : agentsSummary
        ].compactMap { $0 }
        return bits.joined(separator: " • ")
    }

    var tags: [String] {
        var values: [String] = []
        if let project = frontmatter["project"], !project.isEmpty {
            values.append(project)
        }
        if let status = frontmatter["status"], !status.isEmpty {
            values.append(status)
        }
        if let started = frontmatter["started"], !started.isEmpty {
            values.append(started)
        }
        values.append(projectType.label)
        values.append(safetyPosture.label)
        return values
    }

    var isProjectRoot: Bool {
        frontmatter["type"] == "project"
    }
}

struct PublicationStory: Identifiable, Hashable {
    let id: String
    let year: String
    let pdfTitle: String
    let pdfPath: String
    let projectTitle: String
    let projectPath: String
    let projectReadmePath: String
    let matchStatus: String
    let matchBasis: String
    let reviewDecision: String
    let reviewNotes: String

    var pdfURL: URL { URL(fileURLWithPath: pdfPath) }
    var projectURL: URL { URL(fileURLWithPath: projectPath) }
    var projectReadmeURL: URL { URL(fileURLWithPath: projectReadmePath) }
}

struct PublicationProject: Identifiable, Hashable {
    let id: String
    let year: String
    let slug: String
    let path: String
    let readmePath: String
    let title: String
    let quality: String
    let matchedPdfCount: Int
    let matchedPdfTitles: [String]
    let publishedStatus: String

    var url: URL { URL(fileURLWithPath: path) }
    var readmeURL: URL { URL(fileURLWithPath: readmePath) }
}

struct PublicationSnapshot {
    let storiesByYear: [String: [PublicationStory]]
    let projectsByYear: [String: [PublicationProject]]
    let matchedCount: Int
    let missingCount: Int

    static let empty = PublicationSnapshot(
        storiesByYear: [:],
        projectsByYear: [:],
        matchedCount: 0,
        missingCount: 0
    )
}

enum WorkflowKind: String, Codable, CaseIterable {
    case direct
    case shell
}

enum WorkflowSelectionRequirement: String, Codable {
    case none
    case workspaceItem
    case projectRoot
}

enum WorkflowParameterKind: String, Codable, CaseIterable {
    case text
    case multiline
    case number
    case boolean
    case choice
    case path
}

struct WorkflowParameterSpec: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let kind: WorkflowParameterKind
    let helpText: String?
    let defaultValue: String?
    let required: Bool
    let choices: [String]?
    let expandsToMultipleArguments: Bool

    init(
        id: String,
        label: String,
        kind: WorkflowParameterKind,
        helpText: String? = nil,
        defaultValue: String? = nil,
        required: Bool = false,
        choices: [String]? = nil,
        expandsToMultipleArguments: Bool = false
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.helpText = helpText
        self.defaultValue = defaultValue
        self.required = required
        self.choices = choices
        self.expandsToMultipleArguments = expandsToMultipleArguments
    }
}

struct WorkflowDefinition: Identifiable, Hashable {
    let id: String
    let label: String
    let description: String
    let category: String
    let workingDirectoryTemplate: String
    let kind: WorkflowKind
    let executableTemplate: String
    let argumentsTemplate: [String]
    let shellCommandTemplate: String?
    let parameters: [WorkflowParameterSpec]
    let selectionRequirement: WorkflowSelectionRequirement
    let isWriteAction: Bool
    let expectedArtifacts: [String]
    let note: String

    var commandPreview: String {
        switch kind {
        case .direct:
            return ([executableTemplate] + argumentsTemplate).joined(separator: " ")
        case .shell:
            return shellCommandTemplate ?? ""
        }
    }
}

struct WorkflowParameterState: Codable, Hashable {
    var textValues: [String: String] = [:]
    var booleanValues: [String: Bool] = [:]

    mutating func applyDefaults(from specs: [WorkflowParameterSpec]) {
        for spec in specs {
            switch spec.kind {
            case .boolean:
                booleanValues[spec.id] = spec.defaultValue.flatMap(Self.parseBool) ?? false
            default:
                if let value = spec.defaultValue {
                    textValues[spec.id] = value
                } else if textValues[spec.id] == nil {
                    textValues[spec.id] = ""
                }
            }
        }
    }

    func stringValue(for key: String) -> String {
        textValues[key, default: ""]
    }

    func boolValue(for key: String) -> Bool {
        booleanValues[key, default: false]
    }

    static func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
}

struct ResolvedWorkflowCommand {
    let executable: String
    let arguments: [String]
    let workingDirectory: String
    let commandPreview: String
    let estimatedOutputs: [String]
}

struct WorkflowRun: Identifiable, Codable, Hashable {
    let id: String
    let workflowID: String
    let workflowLabel: String
    let startedAt: String
    let finishedAt: String
    let exitCode: Int
    let commandPreview: String
    let workingDirectory: String
    let stdoutPath: String
    let stderrPath: String
    let manifestPath: String
    let artifactPaths: [String]
    let selectionPath: String?
}

struct WorkspaceSnapshot {
    let scannedAt: Date
    let items: [WorkspaceItem]
    let publication: PublicationSnapshot

    static let empty = WorkspaceSnapshot(scannedAt: .now, items: [], publication: .empty)
}

struct PlanningDocument: Identifiable, Hashable {
    let id: String
    let title: String
    let path: String
    let summary: String
    let body: String

    var url: URL { URL(fileURLWithPath: path) }
}

struct PlanningSnapshot {
    let projectPath: String
    let projectTitle: String
    let docs: [PlanningDocument]

    static let empty = PlanningSnapshot(projectPath: "", projectTitle: "Plan Center", docs: [])
}

struct CustomWorkflowPreset: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var description: String
    var category: String
    var workingDirectory: String
    var shellCommand: String
    var selectionRequirement: WorkflowSelectionRequirement
    var isWriteAction: Bool
    var expectedArtifacts: [String]
    var note: String

    init(
        id: String,
        label: String,
        description: String,
        category: String = "Custom",
        workingDirectory: String,
        shellCommand: String,
        selectionRequirement: WorkflowSelectionRequirement = .none,
        isWriteAction: Bool = false,
        expectedArtifacts: [String] = [],
        note: String = ""
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.category = category
        self.workingDirectory = workingDirectory
        self.shellCommand = shellCommand
        self.selectionRequirement = selectionRequirement
        self.isWriteAction = isWriteAction
        self.expectedArtifacts = expectedArtifacts
        self.note = note
    }
}
