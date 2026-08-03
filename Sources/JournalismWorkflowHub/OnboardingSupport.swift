import Foundation

enum AppAppearancePreference: String, CaseIterable, Hashable {
    case system
    case light
    case dark
}

enum OnboardingStep: Int, CaseIterable, Hashable {
    case welcome
    case startMode
    case documentMode
    case workspaceLocation
    case workspaceSetup
    case finish

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .startMode:
            return "How do you want to start?"
        case .documentMode:
            return "How do you handle documents?"
        case .workspaceLocation:
            return "Where should the workspace live?"
        case .workspaceSetup:
            return "Workspace setup"
        case .finish:
            return "Ready to start"
        }
    }
}

enum OnboardingLaunchMode: Hashable {
    case firstRun
    case switchWorkspace

    var title: String {
        switch self {
        case .firstRun:
            return "First-run setup"
        case .switchWorkspace:
            return "Switch workspace"
        }
    }

    var steps: [OnboardingStep] {
        switch self {
        case .firstRun:
            return OnboardingStep.allCases
        case .switchWorkspace:
            return [.workspaceLocation, .workspaceSetup, .finish]
        }
    }

    var initialStep: OnboardingStep {
        steps.first ?? .welcome
    }
}

enum OnboardingStartMode: String, CaseIterable, Hashable {
    case demo
    case existingWorkspace = "existing_workspace"
    case createWorkspace = "create_workspace"

    var label: String {
        switch self {
        case .demo:
            return "Try demo workspace"
        case .existingWorkspace:
            return "Use existing workspace"
        case .createWorkspace:
            return "Create new workspace"
        }
    }

    var summary: String {
        switch self {
        case .demo:
            return "Open the bundled sample workspace and audit the app without touching a real newsroom setup."
        case .existingWorkspace:
            return "Point the app at an existing reporting workspace and validate what works immediately."
        case .createWorkspace:
            return "Create a clean workspace with the standard base folders, starter README.md files, and AGENTS.md guidance."
        }
    }
}

enum OnboardingDocumentMode: String, CaseIterable, Codable, Hashable {
    case localOnly = "local_only"
    case googleDocs = "google_docs"
    case otherSync = "other_sync"

    var label: String {
        switch self {
        case .localOnly:
            return "Local files only"
        case .googleDocs:
            return "Google Docs pointers too"
        case .otherSync:
            return "Other sync setup"
        }
    }

    var summary: String {
        switch self {
        case .localOnly:
            return "Fully supported. The app reads local folders and files directly."
        case .googleDocs:
            return "Partially supported. Google Doc pointers and cache status work; deep provider integration is still limited."
        case .otherSync:
            return "The workspace can live in a locally synced folder, but there is no dedicated Nextcloud, Proton Drive, or similar integration yet."
        }
    }
}

enum OnboardingFirstAction: String, CaseIterable, Codable, Hashable {
    case openOverview = "open_overview"
    case inspectFirstProject = "inspect_first_project"
    case startNewProject = "start_new_project"

    var label: String {
        switch self {
        case .openOverview:
            return "Open workspace overview"
        case .inspectFirstProject:
            return "Inspect first project"
        case .startNewProject:
            return "Start a new project"
        }
    }
}

enum WorkspaceValidationSeverity: Hashable {
    case blocking
    case warning
    case info
}

struct WorkspaceValidationIssue: Identifiable, Hashable {
    let id = UUID()
    let severity: WorkspaceValidationSeverity
    let message: String
}

struct WorkspaceValidationReport: Hashable {
    let path: String
    let issues: [WorkspaceValidationIssue]
    let detectedDirectories: [String]

    var blockingIssues: [WorkspaceValidationIssue] {
        issues.filter { $0.severity == .blocking }
    }

    var warnings: [WorkspaceValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var infos: [WorkspaceValidationIssue] {
        issues.filter { $0.severity == .info }
    }

    var isValid: Bool {
        blockingIssues.isEmpty
    }
}

struct OnboardingDraft: Hashable {
    var startMode: OnboardingStartMode
    var documentMode: OnboardingDocumentMode
    var workspacePath: String
    var createBaseStructure: Bool
    var confirmedSeparateWorkspaceCreation: Bool
    var diagnosticsLoggingEnabled: Bool
    var firstAction: OnboardingFirstAction

    static func initial(defaultNewWorkspacePath: String) -> OnboardingDraft {
        OnboardingDraft(
            startMode: .demo,
            documentMode: .localOnly,
            workspacePath: defaultNewWorkspacePath,
            createBaseStructure: true,
            confirmedSeparateWorkspaceCreation: false,
            diagnosticsLoggingEnabled: true,
            firstAction: .openOverview
        )
    }

    func availableFirstActions(using profile: AppProfile) -> [OnboardingFirstAction] {
        switch startMode {
        case .demo:
            return [.openOverview, .inspectFirstProject]
        case .existingWorkspace, .createWorkspace:
            if profile == .standard {
                return [.openOverview, .inspectFirstProject, .startNewProject]
            }
            return [.openOverview, .inspectFirstProject]
        }
    }

    func needsSeparateWorkspaceConfirmation(
        configuredWorkspacePath: String,
        configuredWorkspaceLooksValid: Bool
    ) -> Bool {
        guard startMode == .createWorkspace,
              configuredWorkspaceLooksValid else {
            return false
        }

        let selected = Self.normalizedPath(workspacePath)
        let configured = Self.normalizedPath(configuredWorkspacePath)
        guard !selected.isEmpty, !configured.isEmpty else {
            return false
        }

        return selected != configured
    }

    func canProceedWithNewWorkspaceCreation(
        selectedPathAlreadyLooksLikeWorkspace: Bool,
        needsExtraConfirmation: Bool
    ) -> Bool {
        createBaseStructure
            && !selectedPathAlreadyLooksLikeWorkspace
            && (!needsExtraConfirmation || confirmedSeparateWorkspaceCreation)
    }

    private static func normalizedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}

struct OnboardingPreferences {
    static let completedKey = "onboardingCompleted"
    static let documentModeKey = "onboardingDocumentMode"
    static let startModeKey = "onboardingStartMode"
    static let firstActionKey = "onboardingFirstAction"
    static let diagnosticsLoggingEnabledKey = "diagnosticsLoggingEnabled"
    static let appAppearancePreferenceKey = "appAppearancePreference"

    static func hasCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey)
    }

    static func persist(draft: OnboardingDraft, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
        defaults.set(draft.documentMode.rawValue, forKey: documentModeKey)
        defaults.set(draft.startMode.rawValue, forKey: startModeKey)
        defaults.set(draft.firstAction.rawValue, forKey: firstActionKey)
        defaults.set(draft.diagnosticsLoggingEnabled, forKey: diagnosticsLoggingEnabledKey)
    }

    static func documentMode(defaults: UserDefaults = .standard) -> OnboardingDocumentMode {
        guard let rawValue = defaults.string(forKey: documentModeKey),
              let mode = OnboardingDocumentMode(rawValue: rawValue) else {
            return .localOnly
        }
        return mode
    }

    static func diagnosticsLoggingEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: diagnosticsLoggingEnabledKey) != nil else {
            return true
        }
        return defaults.bool(forKey: diagnosticsLoggingEnabledKey)
    }

    static func setDiagnosticsLoggingEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: diagnosticsLoggingEnabledKey)
    }

    static func appAppearancePreference(defaults: UserDefaults = .standard) -> AppAppearancePreference {
        guard let rawValue = defaults.string(forKey: appAppearancePreferenceKey),
              let preference = AppAppearancePreference(rawValue: rawValue) else {
            return .system
        }
        return preference
    }

    static func setAppAppearancePreference(_ preference: AppAppearancePreference, defaults: UserDefaults = .standard) {
        defaults.set(preference.rawValue, forKey: appAppearancePreferenceKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
        defaults.removeObject(forKey: documentModeKey)
        defaults.removeObject(forKey: startModeKey)
        defaults.removeObject(forKey: firstActionKey)
        defaults.removeObject(forKey: appAppearancePreferenceKey)
    }
}

struct WorkspaceStructureValidator {
    static let requiredDirectories = ["Projects", "Resources"]
    static let optionalDirectories = ["Areas", "Archives"]

    static func validateExistingWorkspace(
        at url: URL,
        fileManager: FileManager = .default
    ) -> WorkspaceValidationReport {
        var issues: [WorkspaceValidationIssue] = []
        var detectedDirectories: [String] = []

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return WorkspaceValidationReport(
                path: url.path,
                issues: [.init(severity: .blocking, message: "The selected workspace folder does not exist.")],
                detectedDirectories: []
            )
        }

        for name in requiredDirectories {
            let candidate = url.appendingPathComponent(name, isDirectory: true)
            var isRequiredDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isRequiredDirectory), isRequiredDirectory.boolValue {
                detectedDirectories.append(name)
            } else {
                issues.append(.init(severity: .blocking, message: "Missing required folder `\(name)` at the workspace root."))
            }
        }

        for name in optionalDirectories {
            let candidate = url.appendingPathComponent(name, isDirectory: true)
            var isOptionalDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isOptionalDirectory), isOptionalDirectory.boolValue {
                detectedDirectories.append(name)
            } else {
                issues.append(.init(severity: .warning, message: "Optional folder `\(name)` is missing. The app still works without it."))
            }
        }

        if issues.isEmpty {
            issues.append(.init(severity: .info, message: "Workspace structure looks valid for a first run."))
        }

        return WorkspaceValidationReport(path: url.path, issues: issues, detectedDirectories: detectedDirectories)
    }

    static func looksLikeExistingWorkspace(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        validateExistingWorkspace(at: url, fileManager: fileManager).isValid
    }
}

struct WorkspaceBootstrapper {
    let workspaceRoot: URL

    func createBaseStructure(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true, attributes: nil)

        let directories = [
            "Projects",
            "Areas",
            "Resources",
            "Archives"
        ]

        for directory in directories {
            try fileManager.createDirectory(
                at: workspaceRoot.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        try writeIfMissing(
            """
            # Journalism Workflow Workspace

            Local-first reporting workspace for projects, areas, resources, and archives.
            """,
            to: workspaceRoot.appendingPathComponent("README.md"),
            fileManager: fileManager
        )

        try writeIfMissing(
            """
            # AGENTS

            - treat this workspace as local-first
            - preserve provenance of source files
            - prefer minimal, auditable changes
            """,
            to: workspaceRoot.appendingPathComponent("AGENTS.md"),
            fileManager: fileManager
        )

        try writeIfMissing(
            """
            # Projects

            Active reporting and tooling projects live here.
            """,
            to: workspaceRoot.appendingPathComponent("Projects/README.md"),
            fileManager: fileManager
        )
        try writeIfMissing(
            """
            # Areas

            Ongoing responsibilities and monitoring work live here.
            """,
            to: workspaceRoot.appendingPathComponent("Areas/README.md"),
            fileManager: fileManager
        )
        try writeIfMissing(
            """
            # Resources

            Reusable scripts, references, datasets, and templates live here.
            """,
            to: workspaceRoot.appendingPathComponent("Resources/README.md"),
            fileManager: fileManager
        )
        try writeIfMissing(
            """
            # Archives

            Finished or inactive work can move here for traceability.
            """,
            to: workspaceRoot.appendingPathComponent("Archives/README.md"),
            fileManager: fileManager
        )
    }

    private func writeIfMissing(_ contents: String, to url: URL, fileManager: FileManager) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

func defaultNewWorkspacePath(fileManager: FileManager = .default) -> String {
    fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)
        .appendingPathComponent("JournalismWorkflowHub", isDirectory: true)
        .path
}
