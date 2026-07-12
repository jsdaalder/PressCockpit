import Foundation

enum AppProfile: String, Codable, Hashable, CaseIterable {
    case standard
    case standalone

    var label: String {
        switch self {
        case .standard:
            return "Standard"
        case .standalone:
            return "Standalone"
        }
    }

    var showsPlanCenter: Bool {
        self == .standard
    }
}

struct AppConfiguration {
    let profile: AppProfile
    let workspaceRoot: URL
    let demoWorkspaceRoot: URL?

    var isUsingDemoWorkspace: Bool {
        guard let demoWorkspaceRoot else { return false }
        return workspaceRoot.standardizedFileURL == demoWorkspaceRoot.standardizedFileURL
    }
}

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
    case dataJournalism = "data_journalism"
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
    case unknown
    case internalOnly = "internal"
    case localSensitive = "local_sensitive"
    case publishableReviewed = "publishable_reviewed"
    case archival

    var label: String {
        switch self {
        case .unknown: return "Needs review"
        case .internalOnly: return "Internal workspace"
        case .localSensitive: return "Local-only / privacy check"
        case .publishableReviewed: return "Publishable reviewed"
        case .archival: return "Archive reference"
        }
    }
}

enum WorkspaceDocumentProvider: String, Codable, Hashable {
    case localFile = "local_file"
    case googleDocPointer = "google_doc_pointer"

    var label: String {
        switch self {
        case .localFile:
            return "Local file"
        case .googleDocPointer:
            return "Google Doc"
        }
    }
}

enum WorkspaceDocumentRole: String, Codable, Hashable {
    case draft
    case pitch
    case research
    case interviews
    case notes
    case transcript
    case source
    case reference
    case data
    case general

    var label: String {
        switch self {
        case .draft:
            return "Draft"
        case .pitch:
            return "Pitch"
        case .research:
            return "Research"
        case .interviews:
            return "Interviews"
        case .notes:
            return "Notes"
        case .transcript:
            return "Transcript"
        case .source:
            return "Source"
        case .reference:
            return "Reference"
        case .data:
            return "Data"
        case .general:
            return "General"
        }
    }
}

enum WorkspaceDocumentCacheState: String, Codable, Hashable {
    case localFile = "local_file"
    case notCached = "not_cached"
    case placeholder
    case titleStub = "title_stub"
    case cachedSummary = "cached_summary"
    case cachedText = "cached_text"
    case unknown

    var label: String {
        switch self {
        case .localFile:
            return "Local"
        case .notCached:
            return "Not cached"
        case .placeholder:
            return "Placeholder cache"
        case .titleStub:
            return "Stub cached"
        case .cachedSummary:
            return "Summary cached"
        case .cachedText:
            return "Text cached"
        case .unknown:
            return "Status unknown"
        }
    }
}

enum WorkspaceDocumentFreshness: String, Hashable {
    case localFile = "local_file"
    case needsFetch = "needs_fetch"
    case fresh
    case aging
    case stale
    case undated

    var label: String {
        switch self {
        case .localFile:
            return "Local"
        case .needsFetch:
            return "Needs fetch"
        case .fresh:
            return "Fresh"
        case .aging:
            return "Aging"
        case .stale:
            return "Stale"
        case .undated:
            return "Undated"
        }
    }
}

struct WorkspaceDocument: Identifiable, Hashable, Codable {
    let id: String
    let path: String
    let title: String
    let fileExtension: String
    let provider: WorkspaceDocumentProvider
    let role: WorkspaceDocumentRole
    let cacheState: WorkspaceDocumentCacheState
    let externalURL: String?
    let docID: String?
    let cachePath: String?
    let cachedOn: String?

    var url: URL { URL(fileURLWithPath: path) }
    var cacheURL: URL? { cachePath.map(URL.init(fileURLWithPath:)) }

    func freshness(referenceDate: Date = .now) -> WorkspaceDocumentFreshness {
        switch provider {
        case .localFile:
            return .localFile
        case .googleDocPointer:
            break
        }

        switch cacheState {
        case .notCached, .placeholder:
            return .needsFetch
        case .titleStub, .cachedSummary, .cachedText, .unknown, .localFile:
            break
        }

        guard let cachedOnDate = cachedOnDate else {
            return .undated
        }

        let calendar = Calendar(identifier: .gregorian)
        let startOfReferenceDate = calendar.startOfDay(for: referenceDate)
        let startOfCachedDate = calendar.startOfDay(for: cachedOnDate)
        let days = calendar.dateComponents([.day], from: startOfCachedDate, to: startOfReferenceDate).day ?? 0

        switch days {
        case ..<0:
            return .fresh
        case 0...3:
            return .fresh
        case 4...14:
            return .aging
        default:
            return .stale
        }
    }

    private var cachedOnDate: Date? {
        guard let cachedOn, !cachedOn.isEmpty else { return nil }
        return Self.cachedOnFormatter.date(from: cachedOn)
    }

    private static let cachedOnFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var overviewIconName: String {
        switch role {
        case .draft:
            return "doc.text"
        case .pitch:
            return "lightbulb"
        case .research:
            return "magnifyingglass"
        case .interviews:
            return "person.2"
        case .notes:
            return "note.text"
        case .transcript:
            return "text.alignleft"
        case .source:
            return "link"
        case .reference:
            return "bookmark"
        case .data:
            return "tablecells"
        case .general:
            return "doc"
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

struct WorkspaceItem: Identifiable, Hashable, Codable {
    let id: String
    let section: WorkspaceSection
    let path: String
    let readmePath: String?
    let agentsPath: String?
    let title: String
    let summary: String
    let agentsSummary: String
    let frontmatter: [String: String]
    let googleDriveFolderURL: String?
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
    let documents: [WorkspaceDocument]

    var url: URL { URL(fileURLWithPath: path) }
    var readmeURL: URL? { readmePath.map(URL.init(fileURLWithPath:)) }
    var agentsURL: URL? { agentsPath.map(URL.init(fileURLWithPath:)) }
    var googleDriveURL: URL? { googleDriveFolderURL.flatMap(URL.init(string:)) }

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

    var hasGoogleDocPointers: Bool {
        documents.contains { $0.provider == .googleDocPointer }
    }

    var primaryDocuments: [WorkspaceDocument] {
        var selected: [WorkspaceDocument] = []
        var selectedRoles: Set<WorkspaceDocumentRole> = []
        for role in Self.overviewDocumentRoles {
            guard let document = preferredDocument(for: role), !selected.contains(document) else {
                continue
            }
            selected.append(document)
            selectedRoles.insert(document.role)
            if selected.count == 3 {
                return selected
            }
        }

        for document in documents.sorted(by: Self.compareDocuments)
        where !selected.contains(document) && !selectedRoles.contains(document.role) {
            selected.append(document)
            selectedRoles.insert(document.role)
            if selected.count == 3 {
                break
            }
        }
        return selected
    }

    private func preferredDocument(for role: WorkspaceDocumentRole) -> WorkspaceDocument? {
        documents
            .filter { $0.role == role }
            .sorted(by: Self.compareOverviewDocuments)
            .first
    }

    private static let overviewDocumentRoles: [WorkspaceDocumentRole] = [
        .draft, .pitch, .research, .interviews, .notes, .transcript, .source, .reference, .data, .general
    ]

    private static func compareDocuments(_ lhs: WorkspaceDocument, _ rhs: WorkspaceDocument) -> Bool {
        let lhsRole = documentRolePriority(lhs.role)
        let rhsRole = documentRolePriority(rhs.role)
        if lhsRole != rhsRole {
            return lhsRole < rhsRole
        }

        let lhsCache = documentCachePriority(lhs.cacheState)
        let rhsCache = documentCachePriority(rhs.cacheState)
        if lhsCache != rhsCache {
            return lhsCache < rhsCache
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func compareOverviewDocuments(_ lhs: WorkspaceDocument, _ rhs: WorkspaceDocument) -> Bool {
        let lhsProvider = documentProviderPriority(lhs.provider)
        let rhsProvider = documentProviderPriority(rhs.provider)
        if lhsProvider != rhsProvider {
            return lhsProvider < rhsProvider
        }

        let lhsFreshness = documentFreshnessPriority(lhs.freshness())
        let rhsFreshness = documentFreshnessPriority(rhs.freshness())
        if lhsFreshness != rhsFreshness {
            return lhsFreshness < rhsFreshness
        }

        let lhsCache = documentCachePriority(lhs.cacheState)
        let rhsCache = documentCachePriority(rhs.cacheState)
        if lhsCache != rhsCache {
            return lhsCache < rhsCache
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func documentRolePriority(_ role: WorkspaceDocumentRole) -> Int {
        switch role {
        case .draft:
            return 0
        case .pitch:
            return 1
        case .research:
            return 2
        case .interviews:
            return 3
        case .notes:
            return 4
        case .transcript:
            return 5
        case .source:
            return 6
        case .reference:
            return 7
        case .data:
            return 8
        case .general:
            return 9
        }
    }

    private static func documentCachePriority(_ state: WorkspaceDocumentCacheState) -> Int {
        switch state {
        case .localFile:
            return 0
        case .cachedText:
            return 1
        case .cachedSummary:
            return 2
        case .titleStub:
            return 3
        case .placeholder:
            return 4
        case .notCached:
            return 5
        case .unknown:
            return 6
        }
    }

    private static func documentProviderPriority(_ provider: WorkspaceDocumentProvider) -> Int {
        switch provider {
        case .googleDocPointer:
            return 0
        case .localFile:
            return 1
        }
    }

    private static func documentFreshnessPriority(_ freshness: WorkspaceDocumentFreshness) -> Int {
        switch freshness {
        case .fresh, .localFile:
            return 0
        case .aging:
            return 1
        case .undated:
            return 2
        case .needsFetch:
            return 3
        case .stale:
            return 4
        }
    }
}

struct PublicationStory: Identifiable, Hashable, Codable {
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

struct PublicationProject: Identifiable, Hashable, Codable {
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

struct PublicationSnapshot: Codable {
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

enum WorkflowRuntimeKind: String, Codable, Hashable, CaseIterable {
    case generic
    case pythonScript = "python_script"
    case pythonModule = "python_module"
    case shell
}

enum WorkflowAvailability: String, Codable, Hashable, CaseIterable {
    case portable
    case optionalLocal = "optional_local"
    case privateHidden = "private_hidden"

    var label: String {
        switch self {
        case .portable:
            return "Portable"
        case .optionalLocal:
            return "Local"
        case .privateHidden:
            return "Private"
        }
    }
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
    let availability: WorkflowAvailability
    let runtimeKind: WorkflowRuntimeKind
    let workingDirectoryTemplate: String
    let kind: WorkflowKind
    let executableTemplate: String
    let argumentsTemplate: [String]
    let shellCommandTemplate: String?
    let parameters: [WorkflowParameterSpec]
    let selectionRequirement: WorkflowSelectionRequirement
    let isWriteAction: Bool
    let expectedArtifacts: [String]
    let requiredExecutables: [String]
    let requiredPaths: [String]
    let requiredPythonModules: [String]
    let setupHint: String?
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

enum WorkflowPreflightStatus: String, Hashable {
    case ready
    case needsSelection = "needs_selection"
    case missingWorkingDirectory = "missing_working_directory"
    case missingExecutable = "missing_executable"
    case missingRequiredPath = "missing_required_path"
    case missingPythonModule = "missing_python_module"
    case invalidConfiguration = "invalid_configuration"

    var label: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsSelection:
            return "Needs selection"
        case .missingWorkingDirectory:
            return "Missing folder"
        case .missingExecutable:
            return "Needs setup"
        case .missingRequiredPath:
            return "Missing files"
        case .missingPythonModule:
            return "Needs Python setup"
        case .invalidConfiguration:
            return "Invalid"
        }
    }
}

struct WorkflowPreflightReport: Hashable {
    let status: WorkflowPreflightStatus
    let summary: String
    let checkedItems: [String]
    let missingItems: [String]
    let setupHint: String?

    var isRunnable: Bool {
        status == .ready
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

enum ScaffoldPostCreateMode: String, Hashable {
    case created
    case reused
}

struct ScaffoldPostCreateState: Identifiable, Hashable {
    let id: String
    let mode: ScaffoldPostCreateMode
    let projectTitle: String
    let projectRoot: String
    let readmePath: String
    let sourceMaterialChoice: ScaffoldSourceMaterialChoice
    let shouldAutoPromptForDocuments: Bool
    var importedPaths: [String] = []

    var importedItemCount: Int {
        importedPaths.count
    }

    var projectURL: URL {
        URL(fileURLWithPath: projectRoot)
    }

    var readmeURL: URL {
        URL(fileURLWithPath: readmePath)
    }

    var docsURL: URL {
        projectURL.appendingPathComponent("docs", isDirectory: true)
    }
}

struct WorkspaceSnapshot: Codable {
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
    var availability: WorkflowAvailability?
    var workingDirectory: String
    var shellCommand: String
    var selectionRequirement: WorkflowSelectionRequirement
    var isWriteAction: Bool
    var expectedArtifacts: [String]
    var runtimeKind: WorkflowRuntimeKind?
    var requiredExecutables: [String]?
    var requiredPaths: [String]?
    var requiredPythonModules: [String]?
    var setupHint: String?
    var note: String

    init(
        id: String,
        label: String,
        description: String,
        category: String = "Custom",
        availability: WorkflowAvailability? = nil,
        workingDirectory: String,
        shellCommand: String,
        selectionRequirement: WorkflowSelectionRequirement = .none,
        isWriteAction: Bool = false,
        expectedArtifacts: [String] = [],
        runtimeKind: WorkflowRuntimeKind? = nil,
        requiredExecutables: [String]? = nil,
        requiredPaths: [String]? = nil,
        requiredPythonModules: [String]? = nil,
        setupHint: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.label = label
        self.description = description
        self.category = category
        self.availability = availability
        self.workingDirectory = workingDirectory
        self.shellCommand = shellCommand
        self.selectionRequirement = selectionRequirement
        self.isWriteAction = isWriteAction
        self.expectedArtifacts = expectedArtifacts
        self.runtimeKind = runtimeKind
        self.requiredExecutables = requiredExecutables
        self.requiredPaths = requiredPaths
        self.requiredPythonModules = requiredPythonModules
        self.setupHint = setupHint
        self.note = note
    }
}
