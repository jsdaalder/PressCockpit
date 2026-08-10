import Foundation

enum SummaryPreviewFormatter {
    static func wordLimitedPreview(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }

        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > limit else {
            return text
        }

        return words.prefix(limit).joined(separator: " ") + "…"
    }
}

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

    static var editableProjectKinds: [WorkspaceProjectType] {
        [.journalism, .dataJournalism, .tooling, .general]
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
    case capture
    case planCenter
    case workspace(String)
    case workflow(String)
    case publication
    case run(String)
}

enum ProjectDocumentImportFeedbackStyle: Hashable {
    case progress
    case success
    case warning
}

struct ProjectDocumentImportFeedback: Identifiable, Hashable {
    let id = UUID()
    let projectPath: String
    let title: String
    let message: String
    let style: ProjectDocumentImportFeedbackStyle
    let showsOpenDocsOverviewAction: Bool
}

struct ProjectDocumentReviewItem: Identifiable, Hashable {
    let id: String
    let sourcePath: String
    let importedPath: String
    let note: String?

    init(sourcePath: String, importedPath: String, note: String? = nil) {
        self.id = importedPath
        self.sourcePath = sourcePath
        self.importedPath = importedPath
        self.note = note
    }

    var displayTitle: String {
        URL(fileURLWithPath: importedPath).lastPathComponent
    }
}

struct ProjectDocumentReviewSession: Identifiable, Hashable {
    let id = UUID()
    let projectPath: String
    let projectTitle: String
    let items: [ProjectDocumentReviewItem]
    let currentIndex: Int

    var currentItem: ProjectDocumentReviewItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var progressLabel: String {
        let total = items.count
        guard total > 0 else { return "No items waiting." }
        return "Item \(currentIndex + 1) of \(total). Work through the newly attached files one at a time and keep the rest out of sight."
    }
}

enum ProjectActivityState: String, Codable, Hashable, CaseIterable {
    case active
    case inactive

    var label: String {
        switch self {
        case .active:
            return "Active"
        case .inactive:
            return "Inactive"
        }
    }

    static func from(frontmatterValue: String?) -> ProjectActivityState? {
        guard let normalized = normalizedProjectStateToken(frontmatterValue) else { return nil }
        return ProjectActivityState(rawValue: normalized)
    }
}

enum ProjectWorkflowStage: String, Codable, Hashable, CaseIterable {
    case lead
    case feasibilityStudy = "feasibility_study"
    case activeInvestigation = "active_investigation"
    case draftingFactChecking = "drafting_fact_checking"
    case deskHeadReview = "desk_head_review"
    case eindredactie
    case published

    var label: String {
        switch self {
        case .lead:
            return "Lead"
        case .feasibilityStudy:
            return "Feasibility study"
        case .activeInvestigation:
            return "Investigation"
        case .draftingFactChecking:
            return "Drafting & fact-checking"
        case .deskHeadReview:
            return "Desk head review"
        case .eindredactie:
            return "Eindredactie"
        case .published:
            return "Published"
        }
    }

    static func from(frontmatterValue: String?) -> ProjectWorkflowStage? {
        guard let normalized = normalizedProjectStateToken(frontmatterValue) else { return nil }
        return ProjectWorkflowStage(rawValue: normalized)
    }
}

enum ProjectInactiveReason: String, Codable, Hashable, CaseIterable {
    case waiting
    case finished
    case discarded
    case parked

    var label: String {
        switch self {
        case .waiting:
            return "Waiting"
        case .finished:
            return "Finished"
        case .discarded:
            return "Discarded"
        case .parked:
            return "Parked"
        }
    }

    static func from(frontmatterValue: String?) -> ProjectInactiveReason? {
        guard let normalized = normalizedProjectStateToken(frontmatterValue) else { return nil }
        return ProjectInactiveReason(rawValue: normalized)
    }
}

struct ProjectState: Hashable {
    let activityState: ProjectActivityState
    let workflowStage: ProjectWorkflowStage
    let inactiveReason: ProjectInactiveReason?

    var badgeLabel: String {
        "\(activityState.label) · \(workflowStage.label)"
    }

    var detailLabel: String {
        if activityState == .inactive, let inactiveReason {
            return "\(activityState.label) · \(workflowStage.label) · \(inactiveReason.label)"
        }
        return badgeLabel
    }

    func legacyLifecycleStatus(isArchivedStorage: Bool) -> ProjectLifecycleStatus {
        if isArchivedStorage {
            return .archived
        }
        if activityState == .active {
            return .active
        }
        if inactiveReason == .finished {
            return .done
        }
        return .onHold
    }

    static func from(frontmatter: [String: String], isArchivedStorage: Bool) -> ProjectState? {
        let legacyStatus = ProjectLifecycleStatus.from(frontmatterStatus: frontmatter["status"])
        let explicitActivity = ProjectActivityState.from(frontmatterValue: frontmatter["activity_state"])
        let explicitWorkflowStage = ProjectWorkflowStage.from(frontmatterValue: frontmatter["workflow_stage"])
        let explicitInactiveReason = ProjectInactiveReason.from(frontmatterValue: frontmatter["inactive_reason"])

        guard explicitActivity != nil || explicitWorkflowStage != nil || explicitInactiveReason != nil || legacyStatus != nil || isArchivedStorage else {
            return nil
        }

        let workflowStage = explicitWorkflowStage ?? defaultWorkflowStage(
            legacyStatus: legacyStatus,
            explicitInactiveReason: explicitInactiveReason,
            isArchivedStorage: isArchivedStorage
        )

        let activityState = explicitActivity
            ?? (explicitInactiveReason != nil ? .inactive : defaultActivityState(legacyStatus: legacyStatus, isArchivedStorage: isArchivedStorage))

        let inactiveReason: ProjectInactiveReason?
        if activityState == .active {
            inactiveReason = nil
        } else {
            inactiveReason = explicitInactiveReason ?? defaultInactiveReason(legacyStatus: legacyStatus, isArchivedStorage: isArchivedStorage)
        }

        return ProjectState(
            activityState: activityState,
            workflowStage: workflowStage,
            inactiveReason: inactiveReason
        )
    }

    private static func defaultActivityState(
        legacyStatus: ProjectLifecycleStatus?,
        isArchivedStorage: Bool
    ) -> ProjectActivityState {
        if isArchivedStorage {
            return .inactive
        }

        switch legacyStatus {
        case .active:
            return .active
        case .onHold, .done, .archived:
            return .inactive
        case nil:
            return .active
        }
    }

    private static func defaultWorkflowStage(
        legacyStatus: ProjectLifecycleStatus?,
        explicitInactiveReason: ProjectInactiveReason?,
        isArchivedStorage: Bool
    ) -> ProjectWorkflowStage {
        if isArchivedStorage || legacyStatus == .done || legacyStatus == .archived || explicitInactiveReason == .finished {
            return .published
        }
        return .activeInvestigation
    }

    private static func defaultInactiveReason(
        legacyStatus: ProjectLifecycleStatus?,
        isArchivedStorage: Bool
    ) -> ProjectInactiveReason {
        if isArchivedStorage {
            return .finished
        }

        switch legacyStatus {
        case .done, .archived:
            return .finished
        case .onHold:
            return .waiting
        case .active, nil:
            return .waiting
        }
    }
}

private func normalizedProjectStateToken(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")

    guard !normalized.isEmpty else { return nil }
    return normalized
}

enum ProjectLifecycleStatus: String, Codable, Hashable, CaseIterable {
    case active
    case onHold = "on_hold"
    case done
    case archived

    var label: String {
        switch self {
        case .active:
            return "Active"
        case .onHold:
            return "On hold"
        case .done:
            return "Finished"
        case .archived:
            return "Archived"
        }
    }

    var requiresOffboarding: Bool {
        self == .done || self == .archived
    }

    static func from(frontmatterStatus: String?) -> ProjectLifecycleStatus? {
        guard let frontmatterStatus else { return nil }
        let normalized = frontmatterStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return ProjectLifecycleStatus(rawValue: normalized)
    }
}

enum ProjectOffboardingOutcome: String, Codable, Hashable, CaseIterable {
    case unknown
    case published
    case unpublished
    case superseded
    case deleted

    var label: String {
        switch self {
        case .unknown:
            return "Not decided yet"
        case .published:
            return "Published"
        case .unpublished:
            return "Useful but unpublished"
        case .superseded:
            return "Superseded"
        case .deleted:
            return "Delete"
        }
    }

    var deletesProject: Bool {
        self == .deleted
    }

    func resultingProjectState(from currentState: ProjectState) -> ProjectState? {
        guard self != .unknown else { return nil }

        let workflowStage: ProjectWorkflowStage
        if self == .published {
            workflowStage = .published
        } else if currentState.workflowStage == .published {
            workflowStage = .activeInvestigation
        } else {
            workflowStage = currentState.workflowStage
        }

        return ProjectState(
            activityState: .inactive,
            workflowStage: workflowStage,
            inactiveReason: self == .superseded || self == .deleted ? .discarded : .finished
        )
    }
}

struct ProjectStatusChangeState: Identifiable, Hashable {
    let id = UUID()
    let projectID: String
    let projectPath: String
    let readmePath: String
    let projectTitle: String
    let currentCompatibilityStatus: ProjectLifecycleStatus
    let targetCompatibilityStatus: ProjectLifecycleStatus
    let currentProjectState: ProjectState
    let projectType: WorkspaceProjectType
    let dossierSlug: String?
    let archiveYear: String
}

struct ProjectDetailsEditState: Identifiable, Hashable {
    let id = UUID()
    let projectID: String
    let projectPath: String
    let readmePath: String
    let projectTitle: String
    let currentDisplayTitle: String
    let initialDisplayTitle: String
    let currentProjectType: WorkspaceProjectType
    let initialProjectType: WorkspaceProjectType
    let currentState: ProjectState
    let initialState: ProjectState
    let currentDossierSlug: String?
    let initialDossierSlug: String?
    let currentIsInDailyFocus: Bool
    let initialIsInDailyFocus: Bool
    let isArchivedStorage: Bool
}

enum MaintenanceItemKind: String, Codable, Hashable, CaseIterable {
    case missingPublishedPDF = "missing_published_pdf"
    case missingProducedSummary = "missing_produced_summary"
    case missingRemainingOpen = "missing_remaining_open"
    case missingImpactSummary = "missing_impact_summary"
    case missingDossierHandoff = "missing_dossier_handoff"

    var label: String {
        switch self {
        case .missingPublishedPDF:
            return "Published PDF missing"
        case .missingProducedSummary:
            return "Produced summary missing"
        case .missingRemainingOpen:
            return "Open questions missing"
        case .missingImpactSummary:
            return "Impact note missing"
        case .missingDossierHandoff:
            return "Dossier handoff missing"
        }
    }
}

struct MaintenanceItem: Identifiable, Codable, Hashable {
    let id: String
    let kind: MaintenanceItemKind
    let projectTitle: String
    let projectPath: String
    let detail: String
    let createdAt: Date
    let source: String
}

enum CaptureRecordState: String, Codable, Hashable, CaseIterable {
    case queued
    case processing
    case needsReview = "needs_review"
    case assigned
    case failed

    var label: String {
        switch self {
        case .queued:
            return "Queued"
        case .processing:
            return "Processing"
        case .needsReview:
            return "Needs review"
        case .assigned:
            return "Assigned"
        case .failed:
            return "Failed"
        }
    }
}

enum CaptureRecordType: String, Codable, Hashable, CaseIterable {
    case file
    case folder
    case note
    case link

    var label: String {
        switch self {
        case .file:
            return "File"
        case .folder:
            return "Folder"
        case .note:
            return "Note"
        case .link:
            return "Link"
        }
    }
}

struct CaptureRecord: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String?
    let originalSourcePath: String?
    let importedStoragePath: String?
    let capturedAt: Date
    let captureType: CaptureRecordType
    let state: CaptureRecordState
    let failureDescription: String?
    let userNote: String?
    let assignedTargetPath: String?
    let assignedAt: Date?
    let assignedDestinationPath: String?

    init(
        id: String,
        displayName: String?,
        originalSourcePath: String?,
        importedStoragePath: String?,
        capturedAt: Date,
        captureType: CaptureRecordType,
        state: CaptureRecordState,
        failureDescription: String?,
        userNote: String?,
        assignedTargetPath: String?,
        assignedAt: Date?,
        assignedDestinationPath: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.originalSourcePath = originalSourcePath
        self.importedStoragePath = importedStoragePath
        self.capturedAt = capturedAt
        self.captureType = captureType
        self.state = state
        self.failureDescription = failureDescription
        self.userNote = userNote
        self.assignedTargetPath = assignedTargetPath
        self.assignedAt = assignedAt
        self.assignedDestinationPath = assignedDestinationPath
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case originalSourcePath
        case importedStoragePath
        case capturedAt
        case captureType
        case state
        case failureDescription
        case userNote
        case assignedTargetPath
        case assignedProjectPath
        case assignedAt
        case assignedDestinationPath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        originalSourcePath = try container.decodeIfPresent(String.self, forKey: .originalSourcePath)
        importedStoragePath = try container.decodeIfPresent(String.self, forKey: .importedStoragePath)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        captureType = try container.decode(CaptureRecordType.self, forKey: .captureType)
        state = try container.decode(CaptureRecordState.self, forKey: .state)
        failureDescription = try container.decodeIfPresent(String.self, forKey: .failureDescription)
        userNote = try container.decodeIfPresent(String.self, forKey: .userNote)
        assignedTargetPath = try container.decodeIfPresent(String.self, forKey: .assignedTargetPath)
            ?? container.decodeIfPresent(String.self, forKey: .assignedProjectPath)
        assignedAt = try container.decodeIfPresent(Date.self, forKey: .assignedAt)
        assignedDestinationPath = try container.decodeIfPresent(String.self, forKey: .assignedDestinationPath)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(originalSourcePath, forKey: .originalSourcePath)
        try container.encodeIfPresent(importedStoragePath, forKey: .importedStoragePath)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(captureType, forKey: .captureType)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(failureDescription, forKey: .failureDescription)
        try container.encodeIfPresent(userNote, forKey: .userNote)
        try container.encodeIfPresent(assignedTargetPath, forKey: .assignedTargetPath)
        try container.encodeIfPresent(assignedAt, forKey: .assignedAt)
        try container.encodeIfPresent(assignedDestinationPath, forKey: .assignedDestinationPath)
    }

    var displayTitle: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        if let importedStoragePath, !importedStoragePath.isEmpty {
            return URL(fileURLWithPath: importedStoragePath).lastPathComponent
        }
        if let originalSourcePath, !originalSourcePath.isEmpty {
            return URL(fileURLWithPath: originalSourcePath).lastPathComponent
        }
        return captureType.label
    }

    var sourceDescription: String {
        if let originalSourcePath, !originalSourcePath.isEmpty {
            return originalSourcePath
        }
        if let importedStoragePath, !importedStoragePath.isEmpty {
            return importedStoragePath
        }
        return "No source path recorded yet."
    }

    var sourceLabel: String {
        switch captureType {
        case .note:
            return "Saved in Capture storage"
        case .folder:
            if let originalSourcePath, !originalSourcePath.isEmpty {
                return originalSourcePath
            }
            return "Imported folder"
        case .file, .link:
            if let originalSourcePath, !originalSourcePath.isEmpty {
                return originalSourcePath
            }
            return sourceDescription
        }
    }

    var typeCue: String {
        switch captureType {
        case .folder:
            return "Folder"
        case .note:
            return "Markdown"
        case .link:
            return "Link"
        case .file:
            let candidate = importedStoragePath ?? originalSourcePath ?? ""
            let ext = URL(fileURLWithPath: candidate).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            if ext.isEmpty {
                return "File"
            }
            return ext.uppercased()
        }
    }

    var capturedAtLabel: String {
        Self.captureTimestampFormatter.string(from: capturedAt)
    }

    private static let captureTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
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
    let displayStateLabel: String
    let safetyPosture: WorkspaceSafetyPosture
    let directFileCount: Int
    let directFolderCount: Int
    let markdownFiles: Int
    let pdfFiles: Int
    let gdocFiles: Int
    let csvFiles: Int
    let xlsxFiles: Int
    let documents: [WorkspaceDocument]

    private enum CodingKeys: String, CodingKey {
        case id
        case section
        case path
        case readmePath
        case agentsPath
        case title
        case summary
        case agentsSummary
        case frontmatter
        case googleDriveFolderURL
        case projectType
        case displayStateLabel = "lifecycleStage"
        case safetyPosture
        case directFileCount
        case directFolderCount
        case markdownFiles
        case pdfFiles
        case gdocFiles
        case csvFiles
        case xlsxFiles
        case documents
    }

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
            projectState?.detailLabel ?? (displayStateLabel.isEmpty ? nil : displayStateLabel),
            agentsSummary.isEmpty ? nil : agentsSummary
        ].compactMap { $0 }
        return bits.joined(separator: " • ")
    }

    var tags: [String] {
        var values: [String] = []
        if let project = frontmatter["project"], !project.isEmpty {
            values.append(project)
        }

        if isProjectRoot {
            let hasExplicitProjectStateFrontmatter = [
                frontmatter["activity_state"],
                frontmatter["workflow_stage"],
                frontmatter["inactive_reason"]
            ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .contains { !$0.isEmpty }

            if let activityState {
                values.append(activityState.rawValue)
            }
            if let workflowStage {
                values.append(workflowStage.rawValue)
            }
            if let inactiveReason {
                values.append(inactiveReason.rawValue)
            }

            // Keep legacy status searchable only for unmigrated project metadata.
            if !hasExplicitProjectStateFrontmatter,
               let status = frontmatter["status"],
               !status.isEmpty {
                values.append(status)
            }
        } else if let status = frontmatter["status"], !status.isEmpty {
            values.append(status)
        }
        if let started = frontmatter["started"], !started.isEmpty {
            values.append(started)
        }
        if isInDailyFocus {
            values.append("daily_focus")
        }
        values.append(projectType.label)
        values.append(safetyPosture.label)
        return values
    }

    var isProjectRoot: Bool {
        frontmatter["type"] == "project"
    }

    var activityState: ProjectActivityState? {
        projectState?.activityState
    }

    var workflowStage: ProjectWorkflowStage? {
        projectState?.workflowStage
    }

    var inactiveReason: ProjectInactiveReason? {
        projectState?.inactiveReason
    }

    var projectState: ProjectState? {
        guard isProjectRoot else { return nil }
        return ProjectState.from(frontmatter: frontmatter, isArchivedStorage: section == .archives)
    }

    var hasExplicitProjectStateFrontmatter: Bool {
        [
            frontmatter["activity_state"],
            frontmatter["workflow_stage"],
            frontmatter["inactive_reason"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }

    var projectStateBadgeLabel: String {
        projectState?.badgeLabel ?? displayStateLabel
    }

    var projectStateDetailLabel: String {
        projectState?.detailLabel ?? displayStateLabel
    }

    var compatibilityStatus: ProjectLifecycleStatus? {
        projectState?.legacyLifecycleStatus(isArchivedStorage: section == .archives)
            ?? ProjectLifecycleStatus.from(frontmatterStatus: frontmatter["status"])
    }

    var isInDailyFocus: Bool {
        guard isProjectRoot else { return false }
        return frontmatterBoolean(frontmatter["daily_focus"])
    }

    var dossierSlug: String? {
        let value = frontmatter["dossier"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var projectDetailRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Project", title),
            ("Project kind", projectType.label),
            ("Activity state", activityState?.label ?? "Not set"),
            ("Workflow stage", workflowStage?.label ?? "Not set")
        ]

        if activityState == .inactive {
            rows.append(("Inactive reason", inactiveReason?.label ?? "Not set"))
        }

        rows.append(("Daily focus", isInDailyFocus ? "Yes" : "No"))
        rows.append(("Dossier", dossierSlug ?? "None linked yet"))
        rows.append(("Handling", safetyPosture.label))
        return rows
    }

    var workingDocumentRows: [(String, String)] {
        var rows: [(String, String)] = []

        if let draft = canonicalDraftDocument {
            rows.append(("Canonical draft", draft.title))
        } else {
            rows.append(("Canonical draft", "Not decided yet"))
        }

        rows.append(("Pitch", pitchDocument?.title ?? "None linked yet"))
        return rows
    }

    var projectTrustRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("Project", title),
            ("Project kind", projectType.label),
            ("Activity state", activityState?.label ?? "Not set"),
            ("Workflow stage", workflowStage?.label ?? "Not set")
        ]

        if activityState == .inactive {
            rows.append(("Inactive reason", inactiveReason?.label ?? "Not set"))
        }

        rows.append(("Daily focus", isInDailyFocus ? "Yes" : "No"))
        rows.append(("Dossier", dossierSlug ?? "None linked yet"))

        if let draft = canonicalDraftDocument {
            rows.append(("Canonical draft", draft.title))
        } else {
            rows.append(("Canonical draft", "Not decided yet"))
        }

        rows.append(("Handling", safetyPosture.label))
        return rows
    }

    var docsDirectoryURL: URL {
        url.appendingPathComponent("docs", isDirectory: true)
    }

    var docsOverviewURL: URL {
        docsDirectoryURL.appendingPathComponent("docs_overview.md")
    }

    var hasDocsOverview: Bool {
        FileManager.default.fileExists(atPath: docsOverviewURL.path)
    }

    var hasGoogleDocPointers: Bool {
        documents.contains { $0.provider == .googleDocPointer }
    }

    var canonicalDraftDocument: WorkspaceDocument? {
        preferredCanonicalDocument(for: .draft)
    }

    var pitchDocument: WorkspaceDocument? {
        preferredCanonicalDocument(for: .pitch)
    }

    var overviewShortcutDocuments: [WorkspaceDocument] {
        if let draft = canonicalDraftDocument {
            return [draft]
        }

        for role in [WorkspaceDocumentRole.pitch, .research, .interviews, .notes, .transcript] {
            if let document = preferredCanonicalDocument(for: role) {
                return [document]
            }
        }

        return []
    }

    var primaryDocuments: [WorkspaceDocument] {
        var selected: [WorkspaceDocument] = []
        var selectedRoles: Set<WorkspaceDocumentRole> = []
        for role in Self.overviewDocumentRoles {
            guard let document = preferredCanonicalDocument(for: role), !selected.contains(document) else {
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

    func isLikelyDerivedSnapshot(_ document: WorkspaceDocument) -> Bool {
        guard document.provider == .localFile else { return false }

        let normalizedPath = document.path.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if normalizedPath.contains("/_derived/") || normalizedPath.contains("/derived/") {
            return true
        }

        let normalizedTitle = Self.normalizedDocumentIdentity(document.title)
        let snapshotTokens = ["snapshot", "cached", "cache", "export", "download", "analysis"]
        if snapshotTokens.contains(where: { normalizedTitle.contains($0) }) {
            return true
        }

        guard document.role == .draft else {
            return false
        }

        let siblingDraftPointers = documents
            .filter { $0.provider == .googleDocPointer && $0.role == .draft }
            .map { Self.normalizedDocumentIdentity($0.title) }

        return siblingDraftPointers.contains(normalizedTitle)
    }

    private func preferredCanonicalDocument(for role: WorkspaceDocumentRole) -> WorkspaceDocument? {
        if let explicitDocument = explicitCanonicalDocument(for: role) {
            return explicitDocument
        }

        let roleDocuments = documents.filter { $0.role == role }
        guard !roleDocuments.isEmpty else { return nil }

        if role == .draft {
            if let promotedGoogleDraft = roleDocuments
                .filter(isExplicitPromotedGoogleDraft)
                .sorted(by: Self.compareOverviewDocuments)
                .first {
                return promotedGoogleDraft
            }

            if let localDraft = roleDocuments
                .filter({ $0.provider == .localFile && !isLikelyDerivedSnapshot($0) })
                .sorted(by: Self.compareOverviewDocuments)
                .first {
                return localDraft
            }

            if let googleDraft = roleDocuments
                .filter({ $0.provider == .googleDocPointer })
                .sorted(by: Self.compareOverviewDocuments)
                .first {
                return googleDraft
            }
        }

        return roleDocuments.sorted(by: Self.compareOverviewDocuments).first
    }

    private func explicitCanonicalDocument(for role: WorkspaceDocumentRole) -> WorkspaceDocument? {
        guard let configuredPath = explicitCanonicalDocumentPath(for: role) else { return nil }

        let projectURL = url.standardizedFileURL
        let normalizedConfiguredPath = Self.normalizedConfiguredDocumentPath(configuredPath)

        return documents
            .sorted(by: Self.compareOverviewDocuments)
            .first { document in
                let documentURL = document.url.standardizedFileURL
                if Self.normalizedConfiguredDocumentPath(documentURL.path) == normalizedConfiguredPath {
                    return true
                }

                guard documentURL.path.hasPrefix(projectURL.path + "/") else {
                    return false
                }

                let relativePath = String(documentURL.path.dropFirst(projectURL.path.count + 1))
                return Self.normalizedConfiguredDocumentPath(relativePath) == normalizedConfiguredPath
            }
    }

    private func explicitCanonicalDocumentPath(for role: WorkspaceDocumentRole) -> String? {
        let key: String
        switch role {
        case .draft:
            key = "canonical_draft"
        case .pitch:
            key = "canonical_pitch"
        default:
            return nil
        }

        let value = frontmatter[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func isExplicitPromotedGoogleDraft(_ document: WorkspaceDocument) -> Bool {
        guard document.provider == .googleDocPointer, document.role == .draft else {
            return false
        }

        return URL(fileURLWithPath: document.path).lastPathComponent.localizedCaseInsensitiveCompare(
            DraftSupport.defaultGoogleDraftPointerFilename
        ) == .orderedSame
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

    private static func normalizedConfiguredDocumentPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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

    private static func normalizedDocumentIdentity(_ value: String) -> String {
        let normalized = value
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        let mappedScalars = normalized.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        return String(mappedScalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

private func frontmatterBoolean(_ value: String?) -> Bool {
    guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !normalized.isEmpty else {
        return false
    }

    switch normalized {
    case "true", "yes", "1", "on":
        return true
    default:
        return false
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

    var isAwaitingImmediateDocumentImport: Bool {
        sourceMaterialChoice == .now && importedPaths.isEmpty
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
