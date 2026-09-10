import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    private(set) var appProfile: AppProfile
    private(set) var workspaceRoot: URL
    private(set) var demoWorkspaceRoot: URL?

    @Published var snapshot: WorkspaceSnapshot = .empty
    @Published var planningSnapshot: PlanningSnapshot = .empty
    @Published var workflows: [WorkflowDefinition] = []
    @Published var runs: [WorkflowRun] = []
    @Published var selection: SidebarSelection = .overview
    @Published var selectedWorkspaceItemID: String?
    @Published var selectedWorkflowID: String?
    @Published var searchText: String = ""
    @Published var selectedInputs: [String: WorkflowParameterState] = [:]
    @Published var statusMessage: String = "Ready"
    @Published var activeAlert: AppAlert?
    @Published var projectDocumentImportFeedback: ProjectDocumentImportFeedback?
    @Published var projectDocumentReviewSession: ProjectDocumentReviewSession?
    @Published var isRunning: Bool = false
    @Published var selectedRunOutput: String = ""
    @Published private(set) var documentMode: OnboardingDocumentMode
    @Published private(set) var isDiagnosticsLoggingEnabled: Bool
    @Published private(set) var appAppearancePreference: AppAppearancePreference
    @Published var hasCompletedOnboarding: Bool
    @Published private(set) var onboardingLaunchMode: OnboardingLaunchMode?
    @Published private(set) var captureRecords: [CaptureRecord] = []
    @Published private(set) var maintenanceItems: [MaintenanceItem] = []
    @Published var scaffoldProjectWizardDraft = ScaffoldProjectWizardDraft()
    @Published var scaffoldProjectWizardStep: ScaffoldProjectWizardStep = .workingTitle
    @Published var scaffoldPostCreateState: ScaffoldPostCreateState?
    @Published var projectStatusChangeState: ProjectStatusChangeState?
    @Published var projectDetailsEditState: ProjectDetailsEditState?
    @Published private(set) var isFinishingScaffoldPostCreate: Bool = false
    @Published private(set) var hiddenWorkflowCount: Int = 0
    @Published private(set) var workflowPreflightReports: [String: WorkflowPreflightReport] = [:]
    @Published private(set) var canNavigateBack: Bool = false
    @Published private(set) var canNavigateForward: Bool = false

    private var scanner: WorkspaceScanner
    private var catalog: any WorkspaceCataloging
    private var captureStore: any CapturePersisting
    private var maintenanceStore: any MaintenancePersisting
    private var workspaceQueries: WorkspaceQueryStore = .empty
    private var runner: CommandRunner
    private var backHistory: [SidebarSelection] = []
    private var forwardHistory: [SidebarSelection] = []
    private let userDefaults: UserDefaults
    private let appSupportDirectory: URL
    private let revealInFinder: ([URL]) -> Void

    init(
        configuration: AppConfiguration = AppDefaults.configuration,
        catalog: (any WorkspaceCataloging)? = nil,
        captureStore: (any CapturePersisting)? = nil,
        maintenanceStore: (any MaintenancePersisting)? = nil,
        defaults: UserDefaults = .standard,
        supportDirectory: URL? = nil,
        revealInFinder: @escaping ([URL]) -> Void = { urls in
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    ) {
        let hasCompletedOnboarding = OnboardingPreferences.hasCompleted(defaults: defaults)
        let appSupportDirectory = supportDirectory ?? journalismWorkflowHubSupportDirectory()
        self.appProfile = configuration.profile
        self.workspaceRoot = configuration.workspaceRoot
        self.demoWorkspaceRoot = configuration.demoWorkspaceRoot
        self.userDefaults = defaults
        self.appSupportDirectory = appSupportDirectory
        self.revealInFinder = revealInFinder
        self.documentMode = OnboardingPreferences.documentMode(defaults: defaults)
        self.isDiagnosticsLoggingEnabled = OnboardingPreferences.diagnosticsLoggingEnabled(defaults: defaults)
        self.appAppearancePreference = OnboardingPreferences.appAppearancePreference(defaults: defaults)
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.onboardingLaunchMode = hasCompletedOnboarding ? nil : .firstRun
        self.scanner = WorkspaceScanner(workspaceRoot: configuration.workspaceRoot)
        self.catalog = catalog ?? WorkspaceCatalogStore(workspaceRoot: configuration.workspaceRoot)
        self.captureStore = captureStore ?? CaptureStore(workspaceRoot: configuration.workspaceRoot)
        self.maintenanceStore = maintenanceStore ?? MaintenanceStore(workspaceRoot: configuration.workspaceRoot)
        self.runner = CommandRunner(workspaceRoot: configuration.workspaceRoot, appProfile: configuration.profile)
        AppDebugLog.record(
            "[jwh] launch profile=\(configuration.profile.rawValue) workspaceMode=\(configuration.isUsingDemoWorkspace ? "demo" : "connected")",
            enabled: self.isDiagnosticsLoggingEnabled,
            supportDirectory: appSupportDirectory
        )
        if configuration.profile == .standard {
            WorkspaceRootResolver.persist(configuration.workspaceRoot)
        }
        WorkspaceRootResolver.persistProfile(configuration.profile)
        reloadAll()
    }

    var shouldShowOnboarding: Bool {
        onboardingLaunchMode != nil
    }

    func reloadAll() {
        reloadWorkspaceQueryState()
        reloadCaptureState()
        reloadMaintenanceState()
        reloadPlanning()
        reloadWorkflows()
        reloadRuns()
    }

    func reloadWorkspace() {
        reloadWorkspaceQueryState()
        reloadMaintenanceState()
    }

    func reloadPlanning() {
        planningSnapshot = PlanningStore(workspaceRoot: workspaceRoot, profile: appProfile).load()
    }

    func reloadWorkflows() {
        let registry = WorkflowRegistry(workspaceRoot: workspaceRoot, appProfile: appProfile)
        let allWorkflows = registry.allWorkflows()
        workflows = registry.loadWorkflows(selection: selectedWorkspaceItem)
        hiddenWorkflowCount = max(0, allWorkflows.count - workflows.count)
        for workflow in workflows {
            if selectedInputs[workflow.id] == nil {
                var state = WorkflowParameterState()
                state.applyDefaults(from: workflow.parameters)
                if workflow.selectionRequirement == .workspaceItem, let selected = selectedWorkspaceItem {
                    fillSelectionDefaults(into: &state, workflow: workflow, selection: selected)
                }
                selectedInputs[workflow.id] = state
            } else if var existing = selectedInputs[workflow.id] {
                existing.applyDefaults(from: workflow.parameters)
                selectedInputs[workflow.id] = existing
            }
        }
        refreshWorkflowPreflightReports()
    }

    func reloadRuns() {
        runs = loadRuns()
    }

    var selectedWorkspaceItem: WorkspaceItem? {
        workspaceQueries.item(id: selectedWorkspaceItemID)
    }

    func projectDocumentImportFeedback(for item: WorkspaceItem?) -> ProjectDocumentImportFeedback? {
        guard let item else { return nil }
        guard projectDocumentImportFeedback?.projectPath == item.path else { return nil }
        return projectDocumentImportFeedback
    }

    func dismissProjectDocumentImportFeedback(for item: WorkspaceItem?) {
        guard let item else { return }
        guard projectDocumentImportFeedback?.projectPath == item.path else { return }
        projectDocumentImportFeedback = nil
    }

    func activeProjectDocumentReviewSession(for item: WorkspaceItem?) -> ProjectDocumentReviewSession? {
        guard let item else { return nil }
        guard projectDocumentReviewSession?.projectPath == item.path else { return nil }
        return projectDocumentReviewSession
    }

    func updateProjectDocumentReviewNote(_ text: String, for importedPath: String) {
        guard var session = projectDocumentReviewSession else { return }
        guard let index = session.items.firstIndex(where: { $0.importedPath == importedPath }) else { return }
        let normalized = text.isEmpty ? nil : text
        var items = session.items
        items[index] = ProjectDocumentReviewItem(
            sourcePath: items[index].sourcePath,
            importedPath: importedPath,
            note: normalized
        )
        session = ProjectDocumentReviewSession(
            projectPath: session.projectPath,
            projectTitle: session.projectTitle,
            items: items,
            currentIndex: session.currentIndex
        )
        projectDocumentReviewSession = session
    }

    func moveToPreviousProjectDocumentReviewItem() {
        guard let session = projectDocumentReviewSession, session.currentIndex > 0 else { return }
        projectDocumentReviewSession = ProjectDocumentReviewSession(
            projectPath: session.projectPath,
            projectTitle: session.projectTitle,
            items: session.items,
            currentIndex: session.currentIndex - 1
        )
    }

    func moveToNextProjectDocumentReviewItem() {
        guard let session = projectDocumentReviewSession else { return }
        guard session.currentIndex + 1 < session.items.count else { return }
        projectDocumentReviewSession = ProjectDocumentReviewSession(
            projectPath: session.projectPath,
            projectTitle: session.projectTitle,
            items: session.items,
            currentIndex: session.currentIndex + 1
        )
    }

    func dismissProjectDocumentReviewSession(for item: WorkspaceItem?) {
        guard let item else { return }
        guard projectDocumentReviewSession?.projectPath == item.path else { return }
        projectDocumentReviewSession = nil
    }

    func pauseProjectDocumentReview(for item: WorkspaceItem?) {
        guard let item else { return }
        guard let session = activeProjectDocumentReviewSession(for: item) else { return }
        let count = session.items.count
        statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(session.projectTitle). Review can be finished later from the project page."
    }

    var selectedWorkflow: WorkflowDefinition? {
        guard let selectedWorkflowID else { return nil }
        return workflows.first(where: { $0.id == selectedWorkflowID })
    }

    var filteredWorkspaceItems: [WorkspaceItem] {
        workspaceQueries.filteredItems(matching: searchText)
    }

    var filteredWorkflows: [WorkflowDefinition] {
        guard !searchText.isEmpty else { return workflows }
        let query = searchText.lowercased()
        return workflows.filter {
            $0.label.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
                || $0.category.lowercased().contains(query)
        }
    }

    var overviewProjectSummaries: [OverviewProjectSummary] {
        OverviewDeriver.projectSummaries(from: workspaceQueries.snapshot, runs: runs)
    }

    var overviewOpenProjectGroups: [OverviewOpenProjectGroup] {
        OverviewDeriver.openProjectGroups(from: workspaceQueries.snapshot, runs: runs)
    }

    var overviewActions: [OverviewActionSummary] {
        OverviewDeriver.suggestedActions(from: workspaceQueries.snapshot, runs: runs)
    }

    var overviewOperations: [OverviewOperationSummary] {
        var operations = OverviewDeriver.operationSummaries(from: workspaceQueries.snapshot, runs: runs)
        if let maintenanceOperation = maintenanceOperationSummary {
            operations.append(maintenanceOperation)
        }
        return operations
    }

    var firstWorkspaceItem: WorkspaceItem? {
        workspaceQueries.firstItem
    }

    var captureStorageDirectory: URL {
        captureStore.storageDirectory
    }

    var captureQueueRecords: [CaptureRecord] {
        captureRecords.filter { $0.state != .assigned }
    }

    var captureTriageRecords: [CaptureRecord] {
        captureQueueRecords.filter { $0.state == .needsReview }
    }

    var captureFailedRecords: [CaptureRecord] {
        captureQueueRecords.filter { $0.state == .failed }
    }

    var captureAssignedRecords: [CaptureRecord] {
        captureRecords
            .filter { $0.state == .assigned }
            .sorted { lhs, rhs in
                let lhsDate = lhs.assignedAt ?? lhs.capturedAt
                let rhsDate = rhs.assignedAt ?? rhs.capturedAt
                return lhsDate > rhsDate
            }
    }

    var captureAssignmentTargets: [WorkspaceItem] {
        workspaceQueries.items
            .filter { item in
                isCaptureAssignmentTarget(item)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var dossierTargets: [WorkspaceItem] {
        workspaceQueries.items
            .filter { $0.section == .areas || $0.section == .resources }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func captureAssignmentLabel(for item: WorkspaceItem) -> String {
        switch item.section {
        case .projects:
            return "\(item.title) • \(item.projectStateDetailLabel)"
        case .areas:
            return "\(item.title) • Area"
        case .resources:
            return "\(item.title) • Resource"
        case .archives:
            return "\(item.title) • Archive"
        }
    }

    func dossierTargetLabel(for item: WorkspaceItem) -> String {
        switch item.section {
        case .areas:
            return "\(item.title) • Area"
        case .resources:
            return "\(item.title) • Resource"
        case .projects, .archives:
            return item.title
        }
    }

    func maintenanceItems(for item: WorkspaceItem?) -> [MaintenanceItem] {
        guard let item else { return [] }
        return maintenanceItems
            .filter { $0.projectPath == item.path }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func workspaceItem(for id: String) -> WorkspaceItem? {
        workspaceQueries.item(id: id)
    }

    var isStandaloneMode: Bool {
        appProfile == .standalone
    }

    var isUsingDemoWorkspace: Bool {
        guard let demoWorkspaceRoot else { return false }
        return workspaceRoot.standardizedFileURL == demoWorkspaceRoot.standardizedFileURL
    }

    var defaultOnboardingDraft: OnboardingDraft {
        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: defaultNewWorkspacePath())
        draft.documentMode = documentMode
        draft.diagnosticsLoggingEnabled = isDiagnosticsLoggingEnabled
        if isUsingDemoWorkspace {
            draft.startMode = .demo
            draft.firstAction = .inspectFirstProject
        } else if appProfile == .standard {
            draft.startMode = .existingWorkspace
            draft.workspacePath = workspaceRoot.path
        }
        return draft
    }

    func select(_ selection: SidebarSelection) {
        applySelection(selection, recordHistory: true, clearForwardHistory: true)
    }

    func goBack() {
        guard let previous = backHistory.popLast() else { return }
        forwardHistory.append(selection)
        applySelection(previous, recordHistory: false, clearForwardHistory: false)
        updateNavigationAvailability()
    }

    func goForward() {
        guard let next = forwardHistory.popLast() else { return }
        backHistory.append(selection)
        applySelection(next, recordHistory: false, clearForwardHistory: false)
        updateNavigationAvailability()
    }

    func ensureSelectedWorkflowDefaults() {
        guard let workflow = selectedWorkflow else { return }
        if selectedInputs[workflow.id] == nil {
            var state = WorkflowParameterState()
            state.applyDefaults(from: workflow.parameters)
            if let selected = selectedWorkspaceItem {
                fillSelectionDefaults(into: &state, workflow: workflow, selection: selected)
            }
            selectedInputs[workflow.id] = state
        }
        refreshWorkflowPreflightReports()
    }

    func setText(_ value: String, for workflowID: String, fieldID: String) {
        var state = selectedInputs[workflowID] ?? WorkflowParameterState()
        state.textValues[fieldID] = value
        selectedInputs[workflowID] = state
        refreshWorkflowPreflightReports()
    }

    func setBool(_ value: Bool, for workflowID: String, fieldID: String) {
        var state = selectedInputs[workflowID] ?? WorkflowParameterState()
        state.booleanValues[fieldID] = value
        selectedInputs[workflowID] = state
        refreshWorkflowPreflightReports()
    }

    func beginProjectStatusChange(for item: WorkspaceItem, targetStatus: ProjectLifecycleStatus) {
        guard item.isProjectRoot else { return }
        guard let readmePath = item.readmePath else {
            activeAlert = AppAlert(
                title: "Missing README",
                message: "This project does not have a root README.md to update."
            )
            return
        }

        let currentProjectState = item.projectState ?? ProjectState(
            activityState: .active,
            workflowStage: .activeInvestigation,
            inactiveReason: nil
        )
        let currentCompatibilityStatus = currentProjectState.legacyLifecycleStatus(isArchivedStorage: item.section == .archives)
        if targetStatus.requiresOffboarding {
            projectStatusChangeState = ProjectStatusChangeState(
                projectID: item.id,
                projectPath: item.path,
                readmePath: readmePath,
                projectTitle: item.title,
                currentCompatibilityStatus: currentCompatibilityStatus,
                targetCompatibilityStatus: targetStatus,
                currentProjectState: currentProjectState,
                projectType: item.projectType,
                dossierSlug: item.dossierSlug,
                archiveYear: archiveYear(for: item)
            )
            return
        }

        let updatedState = quickProjectState(for: targetStatus, basedOn: currentProjectState)
        beginProjectDetailsEditing(for: item, initialState: updatedState, readmePathOverride: readmePath)
    }

    func dismissProjectStatusChange() {
        projectStatusChangeState = nil
    }

    func beginDiscardingProject(_ item: WorkspaceItem) {
        let currentState = item.projectState ?? ProjectState(
            activityState: .active,
            workflowStage: .activeInvestigation,
            inactiveReason: nil
        )
        let discardedState = ProjectState(
            activityState: .inactive,
            workflowStage: currentState.workflowStage,
            inactiveReason: .discarded
        )
        beginProjectDetailsEditing(for: item, initialState: discardedState)
    }

    func beginProjectDetailsEditing(
        for item: WorkspaceItem,
        initialState: ProjectState? = nil,
        readmePathOverride: String? = nil
    ) {
        guard item.isProjectRoot else { return }
        guard let readmePath = readmePathOverride ?? item.readmePath else {
            activeAlert = AppAlert(
                title: "Missing README",
                message: "This project does not have a root README.md to update."
            )
            return
        }

        let currentState = item.projectState ?? ProjectState(
            activityState: .active,
            workflowStage: .activeInvestigation,
            inactiveReason: nil
        )

        let displayTitle = item.frontmatter["project"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? item.title

        projectDetailsEditState = ProjectDetailsEditState(
            projectID: item.id,
            projectPath: item.path,
            readmePath: readmePath,
            projectTitle: item.title,
            currentDisplayTitle: displayTitle,
            initialDisplayTitle: displayTitle,
            currentProjectType: item.projectType,
            initialProjectType: item.projectType,
            currentState: currentState,
            initialState: initialState ?? currentState,
            currentDossierSlug: item.dossierSlug,
            initialDossierSlug: item.dossierSlug,
            currentIsInDailyFocus: item.isInDailyFocus,
            initialIsInDailyFocus: item.isInDailyFocus,
            isArchivedStorage: item.section == .archives
        )
        select(.workspace(item.id))
    }

    func dismissProjectDetailsEdit() {
        projectDetailsEditState = nil
    }

    func toggleDailyFocus(for item: WorkspaceItem) {
        updateProjectDailyFocus(!item.isInDailyFocus, for: item)
    }

    func saveProjectDetailsEdit(
        _ state: ProjectDetailsEditState,
        projectTitle: String,
        projectType: WorkspaceProjectType,
        activityState: ProjectActivityState,
        workflowStage: ProjectWorkflowStage,
        inactiveReason: ProjectInactiveReason?,
        dossierSlug: String?,
        isInDailyFocus: Bool
    ) {
        guard let item = snapshot.items.first(where: { $0.id == state.projectID }) else {
            activeAlert = AppAlert(
                title: "Project not found",
                message: "Reload the workspace and try editing the project details again."
            )
            return
        }

        if activityState == .inactive, inactiveReason == nil {
            activeAlert = AppAlert(
                title: "Inactive reason required",
                message: "Choose why this project is inactive so waiting, finished, and discarded work stay distinct."
            )
            return
        }

        let normalizedTitle = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedTitle.isEmpty {
            activeAlert = AppAlert(
                title: "Project title required",
                message: "Give the project a real title so the detail page and workspace lists stay trustworthy."
            )
            return
        }

        let normalizedState = ProjectState(
            activityState: activityState,
            workflowStage: workflowStage,
            inactiveReason: activityState == .active ? nil : inactiveReason
        )

        updateProjectMetadata(
            title: normalizedTitle,
            projectType: projectType,
            normalizedState,
            dossierSlug: dossierSlug,
            isInDailyFocus: isInDailyFocus,
            for: item,
            compatibilityStatusOverride: normalizedState.legacyLifecycleStatus(isArchivedStorage: state.isArchivedStorage)
        )
        projectDetailsEditState = nil
    }

    func choosePublishedPDF() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.pdf]
        panel.prompt = "Choose PDF"
        panel.message = "Choose the published PDF to copy into this project's docs folder."
        panel.directoryURL = workspaceRoot

        guard panel.runModal() == .OK else { return nil }
        return panel.url?.standardizedFileURL
    }

    func completeProjectOffboarding(
        _ state: ProjectStatusChangeState,
        outcome: ProjectOffboardingOutcome,
        publishedPDFURL: URL?,
        routeToDossier: Bool,
        producedSummary: String,
        remainingOpenSummary: String,
        impactSummary: String
    ) async {
        guard outcome != .unknown else {
            activeAlert = AppAlert(
                title: "Outcome required",
                message: "Choose whether this project ended published, unpublished, superseded, or should be deleted before saving closeout."
            )
            statusMessage = "Choose an explicit offboarding outcome first."
            return
        }

        guard !(outcome.deletesProject && state.targetCompatibilityStatus != .archived) else {
            activeAlert = AppAlert(
                title: "Delete only applies to archived projects",
                message: "Use Delete only when removing a project instead of moving it into Archives."
            )
            statusMessage = "Delete is only available while archiving a project."
            return
        }

        if outcome.deletesProject {
            statusMessage = "Deleting \(state.projectTitle)…"
        } else {
            statusMessage = state.targetCompatibilityStatus == .archived
                ? "Archiving \(state.projectTitle)…"
                : "Finishing \(state.projectTitle)…"
        }

        do {
            let closeout = try await applyProjectOffboarding(
                state: state,
                outcome: outcome,
                publishedPDFURL: publishedPDFURL,
                routeToDossier: routeToDossier,
                producedSummary: producedSummary,
                remainingOpenSummary: remainingOpenSummary,
                impactSummary: impactSummary
            )
            reloadWorkspace()
            reloadMaintenanceState()
            projectStatusChangeState = nil

            if let finalProjectPath = closeout?.finalProjectPath,
               let itemID = workspaceItemID(forPath: finalProjectPath) {
                select(.workspace(itemID))
            } else if state.targetCompatibilityStatus == .archived {
                select(.overview)
            }

            if closeout?.deletedProject == true {
                statusMessage = "\(state.projectTitle) deleted"
            } else if let closeout, let importedPDFPath = closeout.importedPDFPath {
                statusMessage = "\(state.targetCompatibilityStatus.label) — copied \(URL(fileURLWithPath: importedPDFPath).lastPathComponent)"
            } else if let closeout, closeout.maintenanceItemCount > 0 {
                statusMessage = "\(state.projectTitle) marked \(state.targetCompatibilityStatus.label.lowercased()) with \(closeout.maintenanceItemCount) follow-up \(closeout.maintenanceItemCount == 1 ? "item" : "items")"
            } else {
                statusMessage = "\(state.projectTitle) marked \(state.targetCompatibilityStatus.label.lowercased())"
            }
        } catch {
            activeAlert = AppAlert(
                title: "Could not change project status",
                message: error.localizedDescription
            )
            statusMessage = error.localizedDescription
        }
    }

    func runSelectedWorkflow() {
        guard let workflow = selectedWorkflow else { return }
        let state = selectedInputs[workflow.id] ?? WorkflowParameterState()
        runWorkflow(workflow, with: state)
    }

    func runWorkflow(_ workflow: WorkflowDefinition, with state: WorkflowParameterState) {
        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: workspaceRoot,
            selection: selectedWorkspaceItem,
            state: state
        )
        if !report.isRunnable {
            statusMessage = report.summary
            return
        }

        selectedInputs[workflow.id] = state
        refreshWorkflowPreflightReports()

        if workflow.isWriteAction {
            do {
                let registry = WorkflowRegistry(workspaceRoot: workspaceRoot, appProfile: appProfile)
                let resolved = try registry.resolveCommand(
                    workflow: workflow,
                    state: state,
                    selection: selectedWorkspaceItem
                )
                let backups = try createWorkflowWriteBackups(
                    paths: resolved.estimatedOutputs,
                    workspaceRoot: workspaceRoot,
                    supportDirectory: supportDirectory()
                )
                if !backups.isEmpty {
                    statusMessage = "Backed up \(backups.count) \(backups.count == 1 ? "file" : "files") before running \(workflow.label)…"
                }
            } catch {
                statusMessage = error.localizedDescription
                activeAlert = AppAlert(
                    title: "Could not back up files before write action",
                    message: error.localizedDescription
                )
                return
            }
        }

        isRunning = true
        statusMessage = "Running \(workflow.label)…"
        logDiagnostics("workflow-start id=\(workflow.id) writeAction=\(workflow.isWriteAction)")
        let selectionAtRun = selectedWorkspaceItem
        let scaffoldContext = makeScaffoldCompletionContext(
            workflow: workflow,
            state: state,
            draft: scaffoldProjectWizardDraft
        )

        Task {
            do {
                let run = try runner.run(workflow: workflow, state: state, selection: selectionAtRun)
                await MainActor.run {
                    self.finishWorkflowRun(
                        workflow: workflow,
                        run: run,
                        scaffoldContext: scaffoldContext
                    )
                }
            } catch {
                await MainActor.run {
                    self.logDiagnostics("workflow-launch-failed id=\(workflow.id)")
                    self.statusMessage = error.localizedDescription
                    self.activeAlert = AppAlert(
                        title: workflow.id == "scaffold-project" ? "Project creation failed" : "Workflow failed",
                        message: error.localizedDescription
                    )
                    self.isRunning = false
                }
            }
        }
    }

    func completeOnboarding(using draft: OnboardingDraft) throws {
        let configuration = try configuration(for: draft)
        if draft.startMode == .createWorkspace && draft.createBaseStructure {
            try WorkspaceBootstrapper(workspaceRoot: configuration.workspaceRoot).createBaseStructure()
        }

        applyConfiguration(configuration)
        OnboardingPreferences.persist(draft: draft, defaults: userDefaults)
        documentMode = draft.documentMode
        isDiagnosticsLoggingEnabled = draft.diagnosticsLoggingEnabled
        hasCompletedOnboarding = true
        onboardingLaunchMode = nil
        statusMessage = "Workspace ready"
        logDiagnostics(
            "onboarding-complete startMode=\(draft.startMode.rawValue) documentMode=\(draft.documentMode.rawValue)"
        )

        switch draft.firstAction {
        case .openOverview:
            select(.overview)
        case .inspectFirstProject:
            if let firstItem = firstWorkspaceItem {
                select(.workspace(firstItem.id))
            } else {
                select(.overview)
            }
        case .startNewProject:
            if workflows.contains(where: { $0.id == "scaffold-project" }) {
                select(.workflow("scaffold-project"))
            } else {
                select(.overview)
            }
        }
    }

    func beginWorkspaceSwitch() {
        onboardingLaunchMode = .switchWorkspace
        statusMessage = "Choose a workspace root"
    }

    func cancelOnboardingLaunch() {
        onboardingLaunchMode = hasCompletedOnboarding ? nil : .firstRun
        statusMessage = "Ready"
    }

    func reopenOnboarding() {
        onboardingLaunchMode = .firstRun
        hasCompletedOnboarding = false
        OnboardingPreferences.reset(defaults: userDefaults)
    }

    func refreshSelectedRun() {
        guard case .run(let id) = selection else { return }
        selectedRunOutput = loadRunOutput(for: id)
    }

    func openFolder(for item: WorkspaceItem?) {
        guard let item else { return }
        revealInFinder([item.url])
    }

    func openReadme(for item: WorkspaceItem?) {
        guard let item, let readmeURL = item.readmeURL else { return }
        NSWorkspace.shared.open(readmeURL)
    }

    func openPath(_ path: String) {
        revealInFinder([URL(fileURLWithPath: path)])
    }

    func openCaptureStorage() {
        revealInFinder([captureStorageDirectory])
    }

    func setDiagnosticsLoggingEnabled(_ enabled: Bool) {
        guard enabled != isDiagnosticsLoggingEnabled else { return }
        OnboardingPreferences.setDiagnosticsLoggingEnabled(enabled, defaults: userDefaults)
        isDiagnosticsLoggingEnabled = enabled
        statusMessage = enabled
            ? "Local diagnostics logging enabled"
            : "Local diagnostics logging disabled"

        if enabled {
            logDiagnostics("diagnostics enabled from menu")
        }
    }

    func setDarkModeEnabled(_ enabled: Bool) {
        setAppAppearancePreference(enabled ? .dark : .light)
    }

    func followSystemAppearance() {
        setAppAppearancePreference(.system)
    }

    var preferredColorScheme: ColorScheme? {
        switch appAppearancePreference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var isDarkModeMenuEnabled: Bool {
        switch appAppearancePreference {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            return resolvedSystemColorScheme == .dark
        }
    }

    private var resolvedSystemColorScheme: ColorScheme {
        let bestMatch = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? .dark : .light
    }

    private func setAppAppearancePreference(_ preference: AppAppearancePreference) {
        guard preference != appAppearancePreference else { return }
        OnboardingPreferences.setAppAppearancePreference(preference, defaults: userDefaults)
        appAppearancePreference = preference
        switch preference {
        case .system:
            statusMessage = "Following system appearance"
        case .light:
            statusMessage = "Light mode enabled"
        case .dark:
            statusMessage = "Dark mode enabled"
        }
    }

    func revealDiagnosticsLog() {
        let logURL = journalismWorkflowHubLogFileURL(supportDirectory: supportDirectory())
        if FileManager.default.fileExists(atPath: logURL.path) {
            revealInFinder([logURL])
            return
        }

        revealInFinder([
            journalismWorkflowHubLogsDirectory(supportDirectory: supportDirectory())
        ])
    }

    func shareDiagnosticsLog() {
        let logURL = journalismWorkflowHubLogFileURL(supportDirectory: supportDirectory())
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            revealDiagnosticsLog()
            return
        }

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let view = window.contentView else {
            revealDiagnosticsLog()
            return
        }

        let picker = NSSharingServicePicker(items: [logURL])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openDocument(_ document: WorkspaceDocument) {
        switch document.provider {
        case .localFile:
            openURL(document.url)
        case .googleDocPointer:
            if let externalURL = document.externalURL, let url = URL(string: externalURL) {
                openURL(url)
            } else {
                openURL(document.url)
            }
        }
    }

    func openPreferredDraft(for item: WorkspaceItem?) {
        guard let item, let draft = item.canonicalDraftDocument else { return }
        openDocument(draft)
    }

    func linkedDossier(for item: WorkspaceItem?) -> WorkspaceItem? {
        guard let slug = item?.dossierSlug else { return nil }
        return workspaceQueries.items.first { candidate in
            (candidate.section == .areas || candidate.section == .resources)
                && URL(fileURLWithPath: candidate.path).lastPathComponent == slug
        }
    }

    func openLinkedDossier(for item: WorkspaceItem?) {
        guard let item, let slug = item.dossierSlug else { return }

        if let dossier = linkedDossier(for: item) {
            select(.workspace(dossier.id))
            return
        }

        if let dossierDirectory = dossierURL(for: slug, workspaceRoot: workspaceRoot) {
            revealInFinder([dossierDirectory])
        }
    }

    func openDocumentCache(_ document: WorkspaceDocument) {
        guard let cacheURL = document.cacheURL else { return }
        openURL(cacheURL)
    }

    func openDocsOverview(for item: WorkspaceItem?) {
        guard let item else { return }
        openURL(item.docsOverviewURL)
    }

    func openProjectRoot(_ path: String) {
        revealInFinder([URL(fileURLWithPath: path)])
    }

    func openOverviewTarget(_ target: OverviewTarget) {
        switch target {
        case .overview:
            select(.overview)
        case .workspace(let id):
            select(.workspace(id))
        case .workflow(let id):
            select(.workflow(id))
        case .publication:
            select(.publication)
        case .run(let id):
            select(.run(id))
        }
    }

    func dismissScaffoldPostCreate() {
        scaffoldPostCreateState = nil
    }

    func completeScaffoldPostCreate() async {
        guard let state = scaffoldPostCreateState, !isFinishingScaffoldPostCreate else { return }
        guard state.importedItemCount > 0 else {
            dismissScaffoldPostCreate()
            return
        }

        isFinishingScaffoldPostCreate = true
        statusMessage = "Summarizing imported docs into docs overview…"

        do {
            try await summarizeImportedDocsOverview(
                projectRoot: state.projectRoot,
                importedPaths: state.importedPaths
            )
            reloadWorkspace()
            if let itemID = workspaceItemID(forPath: state.projectRoot) {
                select(.workspace(itemID))
            }

            let count = state.importedItemCount
            statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(state.projectTitle) and updated docs overview"
            projectDocumentImportFeedback = ProjectDocumentImportFeedback(
                projectPath: state.projectRoot,
                title: "Docs attached",
                message: projectDocumentImportSuccessMessage(
                    count: count,
                    projectTitle: state.projectTitle,
                    relevanceNote: nil,
                    reviewNotesByPath: [:]
                ),
                style: .success,
                showsOpenDocsOverviewAction: docsOverviewExists(projectRoot: state.projectRoot)
            )
            scaffoldPostCreateState = nil
        } catch {
            let count = state.importedItemCount
            statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(state.projectTitle), but docs overview update failed"
            projectDocumentImportFeedback = ProjectDocumentImportFeedback(
                projectPath: state.projectRoot,
                title: "Docs attached, summary needs review",
                message: projectDocumentImportFailureMessage(
                    count: count,
                    projectTitle: state.projectTitle,
                    relevanceNote: nil,
                    reviewNotesByPath: [:]
                ),
                style: .warning,
                showsOpenDocsOverviewAction: docsOverviewExists(projectRoot: state.projectRoot)
            )
            activeAlert = AppAlert(title: "Could not summarize docs overview", message: error.localizedDescription)
        }

        isFinishingScaffoldPostCreate = false
    }

    func reuseExistingScaffoldProject(
        projectTitle: String,
        projectRoot: String,
        sourceMaterialChoice: ScaffoldSourceMaterialChoice
    ) {
        let readmePath = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("README.md")
            .path
        let stagedDocuments = sourceMaterialChoice == .now ? scaffoldProjectWizardDraft.stagedDocuments : []
        let stagedDocumentDirectoryPath = scaffoldProjectWizardDraft.stagedDocumentDirectoryPath

        presentScaffoldPostCreate(
            mode: .reused,
            projectTitle: projectTitle,
            projectRoot: projectRoot,
            readmePath: readmePath,
            sourceMaterialChoice: sourceMaterialChoice,
            shouldAutoPromptForDocuments: sourceMaterialChoice == .now && stagedDocuments.isEmpty
        )

        var stagedImportSucceeded = true
        do {
            if !stagedDocuments.isEmpty {
                try importStagedDocumentsIntoScaffoldProject(stagedDocuments)
            }
            try cleanupScaffoldWizardStaging(at: stagedDocumentDirectoryPath)
        } catch {
            stagedImportSucceeded = false
            statusMessage = "Using existing project, but staged documents could not be imported"
            activeAlert = AppAlert(title: "Could not import staged documents", message: error.localizedDescription)
        }

        if stagedImportSucceeded {
            statusMessage = sourceMaterialChoice == .now
                ? (stagedDocuments.isEmpty ? "Using existing project. Add documents now." : "Using existing project. Imported staged documents.")
                : "Using existing project"
        }
    }

    func openScaffoldPostCreateProject() {
        guard let state = scaffoldPostCreateState else { return }
        if let itemID = workspaceItemID(forPath: state.projectRoot) {
            select(.workspace(itemID))
        } else {
            openProjectRoot(state.projectRoot)
        }
    }

    func openScaffoldPostCreateReadme() {
        guard let state = scaffoldPostCreateState else { return }
        openURL(state.readmeURL)
    }

    func openScaffoldPostCreateDocsFolder() {
        guard let state = scaffoldPostCreateState else { return }
        openPath(state.docsURL.path)
    }

    func openScaffoldPostCreateDocsOverview() {
        guard let state = scaffoldPostCreateState else { return }
        openURL(state.docsURL.appendingPathComponent("docs_overview.md"))
    }

    func scaffoldPostCreateDraftDocument() -> WorkspaceDocument? {
        guard let state = scaffoldPostCreateState,
              let itemID = workspaceItemID(forPath: state.projectRoot),
              let item = workspaceItem(for: itemID) else {
            return nil
        }
        return item.canonicalDraftDocument
    }

    func createScaffoldDraft() {
        guard let state = scaffoldPostCreateState else { return }

        if let existingDraft = scaffoldPostCreateDraftDocument() {
            openDocument(existingDraft)
            return
        }

        do {
            let destinationURL = try createLocalDraft(
                in: state.projectURL,
                projectTitle: state.projectTitle
            )
            reloadWorkspace()

            if let itemID = workspaceItemID(forPath: state.projectRoot) {
                select(.workspace(itemID))
            }

            statusMessage = "Created draft \(destinationURL.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not create draft", message: error.localizedDescription)
        }
    }

    func createProjectDraft(for item: WorkspaceItem?) {
        guard let item, item.isProjectRoot else { return }

        if let existingDraft = item.canonicalDraftDocument {
            openDocument(existingDraft)
            return
        }

        do {
            let destinationURL = try createLocalDraft(
                in: item.url,
                projectTitle: item.title
            )
            updateCanonicalWorkingDocumentPath(
                destinationURL.lastPathComponent,
                role: .draft,
                for: item,
                successMessage: "Created draft \(destinationURL.lastPathComponent)"
            )
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not create draft", message: error.localizedDescription)
        }
    }

    func createProjectPitch(for item: WorkspaceItem?) {
        guard let item, item.isProjectRoot else { return }

        if let existingPitch = item.pitchDocument {
            openDocument(existingPitch)
            return
        }

        do {
            let destinationURL = try createPitchDocument(
                in: item.url,
                projectTitle: item.title
            )
            updateCanonicalWorkingDocumentPath(
                destinationURL.lastPathComponent,
                role: .pitch,
                for: item,
                successMessage: "Created pitch \(destinationURL.lastPathComponent)"
            )
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not create pitch", message: error.localizedDescription)
        }
    }

    func setCanonicalWorkingDocument(_ document: WorkspaceDocument?, role: WorkspaceDocumentRole, for item: WorkspaceItem) {
        guard let document else {
            clearCanonicalWorkingDocument(for: item, role: role)
            return
        }

        let relativeDocumentPath = relativePath(document.path, from: item.path)
        updateCanonicalWorkingDocumentPath(
            relativeDocumentPath,
            role: role,
            for: item,
            successMessage: "Updated canonical \(role.label.lowercased())"
        )
    }

    func clearCanonicalWorkingDocument(for item: WorkspaceItem?, role: WorkspaceDocumentRole) {
        guard let item, item.isProjectRoot else { return }

        updateCanonicalWorkingDocumentPath(
            nil,
            role: role,
            for: item,
            successMessage: "Cleared explicit \(role.label.lowercased()) selection"
        )
    }

    func addDocumentsToScaffoldProject() {
        guard var state = scaffoldPostCreateState else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose files or folders to copy into this project's docs folder."
        panel.directoryURL = state.projectURL

        guard panel.runModal() == .OK else { return }

        do {
            let importedPaths = try importDocuments(from: panel.urls, into: state.docsURL)
            guard !importedPaths.isEmpty else { return }

            let merged = Array(Set(state.importedPaths + importedPaths)).sorted()
            state.importedPaths = merged
            scaffoldPostCreateState = state
            reloadWorkspace()

            if let itemID = workspaceItemID(forPath: state.projectRoot) {
                select(.workspace(itemID))
            }

            let count = importedPaths.count
            statusMessage = "Imported \(count) \(count == 1 ? "item" : "items") into docs"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addDocumentsToScaffoldWizard() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose files or folders to stage for this project's docs folder."
        panel.directoryURL = workspaceRoot

        guard panel.runModal() == .OK else { return }

        do {
            var draft = scaffoldProjectWizardDraft
            let existingSourcePaths = Set(draft.stagedDocuments.map { normalizedPath($0.sourcePath) })
            let newURLs = panel.urls.filter { !existingSourcePaths.contains(normalizedPath($0.path)) }

            if newURLs.isEmpty {
                statusMessage = "Those documents are already selected"
                return
            }

            let stagingDirectory = try scaffoldWizardStagingDirectory(existingPath: draft.stagedDocumentDirectoryPath)
            let stagedDocuments = try stageScaffoldWizardDocuments(from: newURLs, into: stagingDirectory)
            guard !stagedDocuments.isEmpty else { return }

            draft.stagedDocumentDirectoryPath = stagingDirectory.path
            draft.stagedDocuments.append(contentsOf: stagedDocuments)
            draft.stagedDocuments.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            scaffoldProjectWizardDraft = draft

            let count = stagedDocuments.count
            statusMessage = "Selected \(count) \(count == 1 ? "item" : "items") for import after creation"
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not stage documents", message: error.localizedDescription)
        }
    }

    func removeDocumentFromScaffoldWizard(_ document: ScaffoldStagedDocument) {
        var draft = scaffoldProjectWizardDraft
        draft.stagedDocuments.removeAll { $0.id == document.id }

        do {
            let stagedURL = URL(fileURLWithPath: document.stagedPath)
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try FileManager.default.removeItem(at: stagedURL)
            }
            cleanupScaffoldWizardStagingDirectoryIfNeeded(path: draft.stagedDocumentDirectoryPath, remainingCount: draft.stagedDocuments.count)
            if draft.stagedDocuments.isEmpty {
                draft.stagedDocumentDirectoryPath = ""
            }
            scaffoldProjectWizardDraft = draft
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not remove staged document", message: error.localizedDescription)
        }
    }

    func clearScaffoldWizardDocuments() {
        do {
            try cleanupScaffoldWizardStaging(for: scaffoldProjectWizardDraft)
            var draft = scaffoldProjectWizardDraft
            draft.stagedDocuments = []
            draft.stagedDocumentDirectoryPath = ""
            scaffoldProjectWizardDraft = draft
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not clear staged documents", message: error.localizedDescription)
        }
    }

    func cancelScaffoldProjectWizard() {
        var stagingCleanupError: Error?
        do {
            try cleanupScaffoldWizardStaging(for: scaffoldProjectWizardDraft)
        } catch {
            stagingCleanupError = error
        }

        scaffoldProjectWizardDraft = ScaffoldProjectWizardDraft()
        scaffoldProjectWizardStep = .workingTitle

        if selection == .workflow("scaffold-project"), canNavigateBack {
            goBack()
        } else {
            select(.overview)
        }

        if let stagingCleanupError {
            statusMessage = "Canceled new project setup, but staged documents could not be cleaned up"
            activeAlert = AppAlert(title: "Could not clean up staged documents", message: stagingCleanupError.localizedDescription)
        } else {
            statusMessage = "Canceled new project setup"
        }
    }

    func addDocuments(to item: WorkspaceItem?) {
        guard let item else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Attach"
        panel.message = "Choose files or folders to copy into this project's docs folder."
        panel.directoryURL = item.url

        guard panel.runModal() == .OK else { return }

        do {
            _ = try attachDocumentsToProject(panel.urls, item: item)
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not attach documents", message: error.localizedDescription)
        }
    }

    func finalizeAttachedDocuments(
        for item: WorkspaceItem,
        importedPaths: [String],
        relevanceNote: String? = nil,
        reviewNotesByPath: [String: String] = [:]
    ) async {
        guard item.isProjectRoot else { return }

        do {
            try await summarizeImportedDocsOverview(
                projectRoot: item.path,
                importedPaths: importedPaths,
                relevanceNote: relevanceNote,
                reviewNotesByPath: reviewNotesByPath
            )
            reloadWorkspace()

            if let itemID = workspaceItemID(forPath: item.path) {
                select(.workspace(itemID))
            }

            let count = importedPaths.count
            statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(item.title) and updated docs overview"
            projectDocumentImportFeedback = ProjectDocumentImportFeedback(
                projectPath: item.path,
                title: "Docs attached",
                message: projectDocumentImportSuccessMessage(
                    count: count,
                    projectTitle: item.title,
                    relevanceNote: relevanceNote,
                    reviewNotesByPath: reviewNotesByPath
                ),
                style: .success,
                showsOpenDocsOverviewAction: true
            )
        } catch {
            let count = importedPaths.count
            statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(item.title), but docs overview update failed"
            projectDocumentImportFeedback = ProjectDocumentImportFeedback(
                projectPath: item.path,
                title: "Docs attached, summary needs review",
                message: projectDocumentImportFailureMessage(
                    count: count,
                    projectTitle: item.title,
                    relevanceNote: relevanceNote,
                    reviewNotesByPath: reviewNotesByPath
                ),
                style: .warning,
                showsOpenDocsOverviewAction: item.hasDocsOverview
            )
            activeAlert = AppAlert(
                title: "Could not summarize docs overview",
                message: error.localizedDescription
            )
        }
    }

    func importDocumentsToProject(_ urls: [URL], item: WorkspaceItem) throws -> [String] {
        try importDocuments(from: urls, into: item.docsDirectoryURL)
    }

    @discardableResult
    func attachDocumentsToProject(_ urls: [URL], item: WorkspaceItem) throws -> [String] {
        let importedPaths = try importDocumentsToProject(urls, item: item)
        guard !importedPaths.isEmpty else { return [] }
        reloadWorkspace()

        if let itemID = workspaceItemID(forPath: item.path) {
            select(.workspace(itemID))
        }

        let count = importedPaths.count
        if item.isProjectRoot {
            projectDocumentImportFeedback = nil
            startProjectDocumentReview(for: item, sourceURLs: urls, importedPaths: importedPaths)
            statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(item.title). Review the imported files before updating docs overview."
        } else {
            statusMessage = "Attached \(count) \(count == 1 ? "item" : "items") to \(item.title)"
        }
        return importedPaths
    }

    func completeProjectDocumentReview(for item: WorkspaceItem) async {
        guard let session = activeProjectDocumentReviewSession(for: item) else { return }
        let reviewNotesByPath: [String: String] = Dictionary(
            uniqueKeysWithValues: session.items.compactMap { reviewItem in
                guard let note = reviewItem.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
                return (reviewItem.importedPath, note)
            }
        )
        let count = session.items.count
        let savedFactCount = appendProjectDocumentReviewNotesToFacts(
            session.items,
            projectRoot: item.url
        )

        projectDocumentImportFeedback = ProjectDocumentImportFeedback(
            projectPath: item.path,
            title: "Updating docs overview",
            message: savedFactCount > 0
                ? "Attached \(count) \(count == 1 ? "item" : "items") to \(item.title), saved \(savedFactCount) review \(savedFactCount == 1 ? "note" : "notes") to facts, and are now building the docs overview."
                : "Attached \(count) \(count == 1 ? "item" : "items") to \(item.title). Building the docs overview from the imported material now.",
            style: .progress,
            showsOpenDocsOverviewAction: item.hasDocsOverview
        )
        projectDocumentReviewSession = nil

        await finalizeAttachedDocuments(
            for: item,
            importedPaths: session.items.map(\.importedPath),
            reviewNotesByPath: reviewNotesByPath
        )
    }

    private func startProjectDocumentReview(for item: WorkspaceItem, sourceURLs: [URL], importedPaths: [String]) {
        let pairs = zip(sourceURLs, importedPaths)
        let items = pairs.map { sourceURL, importedPath in
            ProjectDocumentReviewItem(
                sourcePath: sourceURL.standardizedFileURL.path,
                importedPath: importedPath,
                note: nil
            )
        }
        projectDocumentReviewSession = ProjectDocumentReviewSession(
            projectPath: item.path,
            projectTitle: item.title,
            items: items,
            currentIndex: 0
        )
    }

    private func appendProjectDocumentReviewNotesToFacts(
        _ items: [ProjectDocumentReviewItem],
        projectRoot: URL
    ) -> Int {
        items.reduce(into: 0) { count, item in
            guard let note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return }
            let didAppend = (try? appendReviewNoteToFactsFileIfNeeded(
                note: note,
                sourceDisplayName: item.displayTitle,
                assignedDestinationPath: item.importedPath,
                projectRoot: projectRoot
            )) ?? false
            if didAppend {
                count += 1
            }
        }
    }

    private func projectDocumentImportSuccessMessage(
        count: Int,
        projectTitle: String,
        relevanceNote: String?,
        reviewNotesByPath: [String: String]
    ) -> String {
        if relevanceNote != nil {
            return "Attached \(count) \(count == 1 ? "item" : "items") to \(projectTitle), saved your relevance note, and updated the docs overview. Review the imported summary before treating it as settled reporting material."
        }

        let savedNoteCount = reviewNotesByPath.count
        if savedNoteCount > 0 {
            return "Attached \(count) \(count == 1 ? "item" : "items") to \(projectTitle), saved \(savedNoteCount) review \(savedNoteCount == 1 ? "note" : "notes") to facts, and updated the docs overview. Review the imported summary before treating it as settled reporting material."
        }

        return "Attached \(count) \(count == 1 ? "item" : "items") to \(projectTitle) and updated the docs overview. Review the imported summary before treating it as settled reporting material."
    }

    private func projectDocumentImportFailureMessage(
        count: Int,
        projectTitle: String,
        relevanceNote: String?,
        reviewNotesByPath: [String: String]
    ) -> String {
        if relevanceNote != nil {
            return "Attached \(count) \(count == 1 ? "item" : "items") to \(projectTitle), but the docs overview could not be refreshed. Your relevance note was not folded into the project summary yet, so open the docs overview and source files directly before relying on them."
        }

        let savedNoteCount = reviewNotesByPath.count
        if savedNoteCount > 0 {
            return "Attached \(count) \(count == 1 ? "item" : "items") to \(projectTitle), saved \(savedNoteCount) review \(savedNoteCount == 1 ? "note" : "notes") to facts, but the docs overview could not be refreshed. Open the source files and facts directly before relying on the summary layer."
        }

        return "Attached \(count) \(count == 1 ? "item" : "items") to \(projectTitle), but the docs overview could not be refreshed. Open the docs overview and source files directly before relying on them."
    }

    private func docsOverviewExists(projectRoot: String) -> Bool {
        let overviewPath = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("docs_overview.md")
            .path
        return FileManager.default.fileExists(atPath: overviewPath)
    }

    func addCaptureFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add files"
        panel.message = "Choose files to copy into the Capture queue."
        panel.directoryURL = workspaceRoot

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await importCaptureItems(from: urls) }
    }

    func addCaptureFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Add folder"
        panel.message = "Choose one folder to copy into the Capture queue."
        panel.directoryURL = workspaceRoot

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importCaptureItems(from: [url]) }
    }

    func importCaptureItems(from urls: [URL]) async {
        let normalizedURLs = urls.map { $0.standardizedFileURL }
        guard !normalizedURLs.isEmpty else { return }

        let pendingRecords = normalizedURLs.map { sourceURL in
            CaptureRecord(
                id: UUID().uuidString,
                displayName: sourceURL.lastPathComponent,
                originalSourcePath: sourceURL.path,
                importedStoragePath: nil,
                capturedAt: .now,
                captureType: captureRecordType(for: sourceURL),
                state: .queued,
                failureDescription: nil,
                userNote: nil,
                assignedTargetPath: nil,
                assignedAt: nil,
                assignedDestinationPath: nil
            )
        }

        appendCaptureRecords(pendingRecords)
        statusMessage = "Adding \(pendingRecords.count) \(pendingRecords.count == 1 ? "item" : "items") to Capture"

        var successCount = 0
        var failureCount = 0

        for record in pendingRecords {
            updateCaptureRecord(
                record.id,
                state: .processing,
                failureDescription: nil
            )

            do {
                let importedURL = try await copyCaptureItemToStorage(for: record)
                updateCaptureRecord(
                    record.id,
                    importedStoragePath: importedURL.path,
                    state: .needsReview,
                    failureDescription: nil
                )
                successCount += 1
            } catch {
                updateCaptureRecord(
                    record.id,
                    state: .failed,
                    failureDescription: error.localizedDescription
                )
                failureCount += 1
            }
        }

        if failureCount == 0 {
            statusMessage = "Added \(successCount) \(successCount == 1 ? "item" : "items") to Capture"
        } else if successCount == 0 {
            statusMessage = "Could not add \(failureCount) \(failureCount == 1 ? "item" : "items") to Capture"
        } else {
            statusMessage = "Added \(successCount) items to Capture, \(failureCount) failed"
        }
    }

    func saveQuickCaptureNote(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let capturedAt = Date()
        let displayName = captureQuickNoteTitle(from: trimmed)
        let record = CaptureRecord(
            id: UUID().uuidString,
            displayName: displayName,
            originalSourcePath: nil,
            importedStoragePath: nil,
            capturedAt: capturedAt,
            captureType: .note,
            state: .queued,
            failureDescription: nil,
            userNote: nil,
            assignedTargetPath: nil,
            assignedAt: nil,
            assignedDestinationPath: nil
        )

        appendCaptureRecords([record])
        statusMessage = "Saving quick note"

        updateCaptureRecord(record.id, state: .processing, failureDescription: nil)

        do {
            let noteURL = try await writeQuickCaptureNote(
                recordID: record.id,
                displayName: displayName,
                text: trimmed,
                capturedAt: capturedAt
            )
            updateCaptureRecord(
                record.id,
                importedStoragePath: noteURL.path,
                state: .needsReview,
                failureDescription: nil
            )
            statusMessage = "Saved quick note to Capture"
        } catch {
            updateCaptureRecord(
                record.id,
                state: .failed,
                failureDescription: error.localizedDescription
            )
            statusMessage = "Could not save quick note"
        }
    }

    func setCaptureUserNote(_ text: String, for recordID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateCaptureRecord(recordID) { current in
            CaptureRecord(
                id: current.id,
                displayName: current.displayName,
                originalSourcePath: current.originalSourcePath,
                importedStoragePath: current.importedStoragePath,
                capturedAt: current.capturedAt,
                captureType: current.captureType,
                state: current.state,
                failureDescription: current.failureDescription,
                userNote: trimmed.isEmpty ? nil : trimmed,
                assignedTargetPath: current.assignedTargetPath,
                assignedAt: current.assignedAt,
                assignedDestinationPath: current.assignedDestinationPath
            )
        }
    }

    func createPlaceholderProjectFromCaptureRecord(_ recordID: String, note: String) async -> Bool {
        guard let current = captureRecords.first(where: { $0.id == recordID }) else { return false }
        guard current.state != .assigned else { return false }
        guard let importedStoragePath = current.importedStoragePath, !importedStoragePath.isEmpty else {
            statusMessage = "This capture item is not ready to turn into a project yet."
            return false
        }

        let registry = WorkflowRegistry(workspaceRoot: workspaceRoot, appProfile: appProfile)
        guard let workflow = registry.allWorkflows().first(where: { $0.id == "scaffold-project" }) else {
            let message = "The scaffold-project workflow is not available in this workspace."
            statusMessage = message
            activeAlert = AppAlert(title: "Could not create placeholder project", message: message)
            return false
        }

        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = placeholderScaffoldDraft(for: current, note: normalizedNote)
        let state = draft.mappedState(for: workflow, workspaceRoot: workspaceRoot)
        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: workspaceRoot,
            selection: selectedWorkspaceItem,
            state: state
        )
        if !report.isRunnable {
            statusMessage = report.summary
            return false
        }

        if workflow.isWriteAction {
            do {
                let resolved = try registry.resolveCommand(
                    workflow: workflow,
                    state: state,
                    selection: selectedWorkspaceItem
                )
                _ = try createWorkflowWriteBackups(
                    paths: resolved.estimatedOutputs,
                    workspaceRoot: workspaceRoot,
                    supportDirectory: supportDirectory()
                )
            } catch {
                statusMessage = error.localizedDescription
                activeAlert = AppAlert(
                    title: "Could not back up files before project creation",
                    message: error.localizedDescription
                )
                return false
            }
        }

        updateCaptureRecord(recordID) { existing in
            CaptureRecord(
                id: existing.id,
                displayName: existing.displayName,
                originalSourcePath: existing.originalSourcePath,
                importedStoragePath: existing.importedStoragePath,
                capturedAt: existing.capturedAt,
                captureType: existing.captureType,
                state: .processing,
                failureDescription: nil,
                userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                assignedTargetPath: existing.assignedTargetPath,
                assignedAt: existing.assignedAt,
                assignedDestinationPath: existing.assignedDestinationPath
            )
        }

        let projectRoot = state.stringValue(for: "project_root").trimmingCharacters(in: .whitespacesAndNewlines)
        let projectTitle = state.stringValue(for: "title").trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = URL(fileURLWithPath: importedStoragePath)

        isRunning = true
        statusMessage = "Creating placeholder project…"
        logDiagnostics("workflow-start id=\(workflow.id) writeAction=\(workflow.isWriteAction) source=capture")
        defer { isRunning = false }

        do {
            let run = try runner.run(workflow: workflow, state: state, selection: selectedWorkspaceItem)
            reloadRuns()

            guard run.exitCode == 0 else {
                logDiagnostics("workflow-finished id=\(workflow.id) exitCode=\(run.exitCode) source=capture")
                updateCaptureRecord(recordID) { existing in
                    CaptureRecord(
                        id: existing.id,
                        displayName: existing.displayName,
                        originalSourcePath: existing.originalSourcePath,
                        importedStoragePath: existing.importedStoragePath,
                        capturedAt: existing.capturedAt,
                        captureType: existing.captureType,
                        state: .needsReview,
                        failureDescription: "The scaffold script exited with code \(run.exitCode).",
                        userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                        assignedTargetPath: existing.assignedTargetPath,
                        assignedAt: existing.assignedAt,
                        assignedDestinationPath: existing.assignedDestinationPath
                    )
                }
                statusMessage = "Could not create placeholder project"
                activeAlert = AppAlert(
                    title: "Placeholder project creation failed",
                    message: "The scaffold script exited with code \(run.exitCode). Open the latest run for details."
                )
                return false
            }

            logDiagnostics("workflow-finished id=\(workflow.id) exitCode=\(run.exitCode) source=capture")

            let destinationURL = try await copyCaptureRecord(
                from: sourceURL,
                into: URL(fileURLWithPath: projectRoot).appendingPathComponent("docs", isDirectory: true)
            )
            let didAppendFacts = (try? appendReviewNoteToFactsFileIfNeeded(
                note: normalizedNote,
                sourceDisplayName: current.displayTitle,
                assignedDestinationPath: destinationURL.path,
                projectRoot: URL(fileURLWithPath: projectRoot)
            )) ?? false

            updateCaptureRecord(recordID) { existing in
                CaptureRecord(
                    id: existing.id,
                    displayName: existing.displayName,
                    originalSourcePath: existing.originalSourcePath,
                    importedStoragePath: existing.importedStoragePath,
                    capturedAt: existing.capturedAt,
                    captureType: existing.captureType,
                    state: .assigned,
                    failureDescription: nil,
                    userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                    assignedTargetPath: projectRoot,
                    assignedAt: .now,
                    assignedDestinationPath: destinationURL.path
                )
            }

            reloadWorkspace()
            statusMessage = didAppendFacts
                ? "Created placeholder project \(projectTitle) and saved note to facts"
                : "Created placeholder project \(projectTitle)"
            return true
        } catch {
            updateCaptureRecord(recordID) { existing in
                CaptureRecord(
                    id: existing.id,
                    displayName: existing.displayName,
                    originalSourcePath: existing.originalSourcePath,
                    importedStoragePath: existing.importedStoragePath,
                    capturedAt: existing.capturedAt,
                    captureType: existing.captureType,
                    state: .needsReview,
                    failureDescription: error.localizedDescription,
                    userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                    assignedTargetPath: existing.assignedTargetPath,
                    assignedAt: existing.assignedAt,
                    assignedDestinationPath: existing.assignedDestinationPath
                )
            }
            statusMessage = "Could not create placeholder project"
            activeAlert = AppAlert(
                title: "Could not create placeholder project",
                message: error.localizedDescription
            )
            logDiagnostics("workflow-launch-failed id=\(workflow.id) source=capture")
            return false
        }
    }

    func assignCaptureRecord(_ recordID: String, to target: WorkspaceItem, note: String) async {
        guard let current = captureRecords.first(where: { $0.id == recordID }) else { return }
        guard current.state != .assigned else { return }
        guard let importedStoragePath = current.importedStoragePath, !importedStoragePath.isEmpty else {
            statusMessage = "This capture item is not ready to assign yet."
            return
        }

        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updateCaptureRecord(recordID) { existing in
            CaptureRecord(
                id: existing.id,
                displayName: existing.displayName,
                originalSourcePath: existing.originalSourcePath,
                importedStoragePath: existing.importedStoragePath,
                capturedAt: existing.capturedAt,
                captureType: existing.captureType,
                state: .processing,
                failureDescription: nil,
                userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                assignedTargetPath: existing.assignedTargetPath,
                assignedAt: existing.assignedAt,
                assignedDestinationPath: existing.assignedDestinationPath
            )
        }

        do {
            let destinationURL = try await copyCaptureRecord(
                from: URL(fileURLWithPath: importedStoragePath),
                into: target.url.appendingPathComponent("docs", isDirectory: true)
            )
            let didAppendFacts = target.section == .projects
                ? ((try? appendReviewNoteToFactsFileIfNeeded(
                    note: normalizedNote,
                    sourceDisplayName: current.displayTitle,
                    assignedDestinationPath: destinationURL.path,
                    projectRoot: target.url
                )) ?? false)
                : false

            updateCaptureRecord(recordID) { existing in
                CaptureRecord(
                    id: existing.id,
                    displayName: existing.displayName,
                    originalSourcePath: existing.originalSourcePath,
                    importedStoragePath: existing.importedStoragePath,
                    capturedAt: existing.capturedAt,
                    captureType: existing.captureType,
                    state: .assigned,
                    failureDescription: nil,
                    userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                    assignedTargetPath: target.path,
                    assignedAt: .now,
                    assignedDestinationPath: destinationURL.path
                )
            }

            reloadWorkspace()
            statusMessage = didAppendFacts
                ? "Assigned \(current.displayTitle) to \(target.title) and saved note to facts"
                : "Assigned \(current.displayTitle) to \(target.title)"
        } catch {
            updateCaptureRecord(recordID) { existing in
                CaptureRecord(
                    id: existing.id,
                    displayName: existing.displayName,
                    originalSourcePath: existing.originalSourcePath,
                    importedStoragePath: existing.importedStoragePath,
                    capturedAt: existing.capturedAt,
                    captureType: existing.captureType,
                    state: .needsReview,
                    failureDescription: error.localizedDescription,
                    userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                    assignedTargetPath: existing.assignedTargetPath,
                    assignedAt: existing.assignedAt,
                    assignedDestinationPath: existing.assignedDestinationPath
                )
            }
            statusMessage = "Could not assign \(current.displayTitle)"
            activeAlert = AppAlert(
                title: "Could not assign capture item",
                message: error.localizedDescription
            )
        }
    }

    private func isCaptureAssignmentTarget(_ item: WorkspaceItem) -> Bool {
        switch item.section {
        case .projects:
            return item.isProjectRoot && item.inactiveReason != .discarded
        case .areas, .resources:
            return item.isProjectRoot && isTopLevelDossier(item)
        case .archives:
            return false
        }
    }

    private func isTopLevelDossier(_ item: WorkspaceItem) -> Bool {
        let rootComponents = workspaceRoot.standardizedFileURL.pathComponents
        let itemComponents = item.url.standardizedFileURL.pathComponents
        guard itemComponents.starts(with: rootComponents) else { return false }
        let relativeComponents = Array(itemComponents.dropFirst(rootComponents.count))
        guard let topLevelDirectory = relativeComponents.first else { return false }
        guard topLevelDirectory == "Areas" || topLevelDirectory == "Resources" else { return false }
        return relativeComponents.count == 2
    }

    private func placeholderScaffoldDraft(for record: CaptureRecord, note: String) -> ScaffoldProjectWizardDraft {
        var draft = ScaffoldProjectWizardDraft()
        draft.updateWorkingTitle(placeholderProjectTitle(from: record), workspaceRoot: workspaceRoot)
        draft.summaryText = placeholderProjectSummary(note: note)
        draft.sourceMaterialChoice = .later
        draft.syncAdvancedDefaults(workspaceRoot: workspaceRoot)

        let baseFolderName = draft.derivedFolderName
        var candidateIndex = 2
        while !draft.derivedProjectRoot(workspaceRoot: workspaceRoot).isEmpty,
              FileManager.default.fileExists(atPath: draft.derivedProjectRoot(workspaceRoot: workspaceRoot)) {
            draft.updateFolderNameOverride("\(baseFolderName)-\(candidateIndex)", workspaceRoot: workspaceRoot)
            candidateIndex += 1
        }

        return draft
    }

    private func placeholderProjectTitle(from record: CaptureRecord) -> String {
        let rawTitle: String
        if let displayName = record.displayName, !displayName.isEmpty {
            rawTitle = displayName
        } else if let importedStoragePath = record.importedStoragePath, !importedStoragePath.isEmpty {
            rawTitle = URL(fileURLWithPath: importedStoragePath).deletingPathExtension().lastPathComponent
        } else if let originalSourcePath = record.originalSourcePath, !originalSourcePath.isEmpty {
            rawTitle = URL(fileURLWithPath: originalSourcePath).deletingPathExtension().lastPathComponent
        } else {
            rawTitle = "Story hunch"
        }

        let cleaned = rawTitle
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Story hunch" : cleaned
    }

    private func placeholderProjectSummary(note: String) -> String {
        if !note.isEmpty {
            return note
        }
        return "Placeholder project created from Capture. Refine the summary and reporting direction later."
    }

    func archiveCaptureRecord(_ recordID: String) async {
        guard let current = captureRecords.first(where: { $0.id == recordID }) else { return }
        guard let importedStoragePath = current.importedStoragePath, !importedStoragePath.isEmpty else {
            statusMessage = "This capture item does not have a stored copy to archive."
            return
        }

        updateCaptureRecord(
            recordID,
            state: .processing,
            failureDescription: nil
        )

        let sourceURL = URL(fileURLWithPath: importedStoragePath)
        let archiveRoot = workspaceRoot
            .appendingPathComponent("Archives", isDirectory: true)
            .appendingPathComponent("Capture archive", isDirectory: true)

        do {
            _ = try await moveCaptureRecord(from: sourceURL, into: archiveRoot)
            cleanupCaptureContainer(afterRemoving: sourceURL)
            removeCaptureRecord(recordID)
            reloadWorkspace()
            statusMessage = "Archived \(current.displayTitle) to Capture archive"
        } catch {
            updateCaptureRecord(
                recordID,
                state: .failed,
                failureDescription: error.localizedDescription
            )
            statusMessage = "Could not archive \(current.displayTitle)"
        }
    }

    func deleteCaptureRecord(_ recordID: String) async {
        guard let current = captureRecords.first(where: { $0.id == recordID }) else { return }
        guard let importedStoragePath = current.importedStoragePath, !importedStoragePath.isEmpty else {
            removeCaptureRecord(recordID)
            statusMessage = "Deleted \(current.displayTitle) from Capture"
            return
        }

        updateCaptureRecord(
            recordID,
            state: .processing,
            failureDescription: nil
        )

        let sourceURL = URL(fileURLWithPath: importedStoragePath)

        do {
            try await deleteCaptureRecordPayload(at: sourceURL)
            cleanupCaptureContainer(afterRemoving: sourceURL)
            removeCaptureRecord(recordID)
            statusMessage = "Deleted \(current.displayTitle) from Capture"
        } catch {
            updateCaptureRecord(
                recordID,
                state: .failed,
                failureDescription: error.localizedDescription
            )
            statusMessage = "Could not delete \(current.displayTitle)"
        }
    }

    private func reloadWorkspaceQueryState() {
        let liveSnapshot = scanner.scan()
        snapshot = liveSnapshot
        catalog.replace(with: liveSnapshot)
        workspaceQueries = WorkspaceQueryStore(snapshot: catalog.loadSnapshot() ?? liveSnapshot)
    }

    private func reloadCaptureState() {
        switch captureStore.loadCatalog() {
        case .loaded(let catalog):
            let mergedRecords = mergedCaptureRecordsWithRecoveredItems(catalog.records)
            captureRecords = mergedRecords
            if mergedRecords != catalog.records {
                captureStore.replace(with: mergedRecords)
            }
        case .missing:
            let recoveredRecords = captureStore.recoverRecordsFromStorage(excluding: [])
            captureRecords = recoveredRecords
            if !recoveredRecords.isEmpty {
                captureStore.replace(with: recoveredRecords)
            }
        case .unreadable, .workspaceMismatch:
            let recoveredRecords = captureStore.recoverRecordsFromStorage(excluding: [])
            captureRecords = recoveredRecords
        }
    }

    private func reloadMaintenanceState() {
        maintenanceItems = maintenanceStore.load()
    }

    private var maintenanceOperationSummary: OverviewOperationSummary? {
        guard !maintenanceItems.isEmpty else { return nil }
        let target = maintenanceItems.first.flatMap { item -> OverviewTarget? in
            workspaceItemID(forPath: item.projectPath).map(OverviewTarget.workspace)
        } ?? .overview

        return OverviewOperationSummary(
            id: "workspace-maintenance",
            title: "Workspace maintenance queue",
            detail: "\(maintenanceItems.count) closeout \(maintenanceItems.count == 1 ? "follow-up is" : "follow-ups are") waiting, such as missing publication PDFs, optional summaries, or dossier handoff.",
            buttonTitle: "Open project",
            count: maintenanceItems.count,
            target: target
        )
    }

    private func applySelection(
        _ rawSelection: SidebarSelection,
        recordHistory: Bool,
        clearForwardHistory: Bool
    ) {
        let resolvedSelection = normalizedSelection(rawSelection)
        guard resolvedSelection != selection else {
            if clearForwardHistory {
                forwardHistory.removeAll()
                updateNavigationAvailability()
            }
            return
        }

        if recordHistory {
            backHistory.append(selection)
        }
        if clearForwardHistory {
            forwardHistory.removeAll()
        }

        selection = resolvedSelection
        syncSelectionState(for: resolvedSelection)
        updateNavigationAvailability()
    }

    private func normalizedSelection(_ selection: SidebarSelection) -> SidebarSelection {
        if selection == .planCenter && !appProfile.showsPlanCenter {
            return .overview
        }
        return selection
    }

    private func syncSelectionState(for selection: SidebarSelection) {
        switch selection {
        case .workspace(let id):
            selectedWorkspaceItemID = id
            reloadWorkspace()
            if let item = workspaceQueries.item(id: id) {
                logDiagnostics(
                    "workspace-detail section=\(item.section.rawValue) frontmatter=\(item.frontmatter.count) docs=\(item.documents.count) state=\(item.projectStateDetailLabel)"
                )
            } else {
                logDiagnostics("workspace-detail missing")
            }
            reloadWorkflows()
        default:
            refreshWorkflowPreflightReports()
        }

        switch selection {
        case .workflow(let id):
            selectedWorkflowID = id
            ensureSelectedWorkflowDefaults()
        case .run(let id):
            selectedRunOutput = loadRunOutput(for: id)
        default:
            break
        }
    }

    private func updateNavigationAvailability() {
        canNavigateBack = !backHistory.isEmpty
        canNavigateForward = !forwardHistory.isEmpty
    }

    func workflowPreflightReport(for workflow: WorkflowDefinition) -> WorkflowPreflightReport {
        workflowPreflightReports[workflow.id] ?? WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: workspaceRoot,
            selection: selectedWorkspaceItem,
            state: selectedInputs[workflow.id] ?? WorkflowParameterState()
        )
    }

    private func refreshWorkflowPreflightReports() {
        workflowPreflightReports = Dictionary(uniqueKeysWithValues: workflows.map { workflow in
            (
                workflow.id,
                WorkflowPreflightEvaluator.evaluate(
                    workflow: workflow,
                    workspaceRoot: workspaceRoot,
                    selection: selectedWorkspaceItem,
                    state: selectedInputs[workflow.id] ?? WorkflowParameterState()
                )
            )
        })
    }

    private func fillSelectionDefaults(
        into state: inout WorkflowParameterState,
        workflow: WorkflowDefinition,
        selection: WorkspaceItem
    ) {
        for spec in workflow.parameters {
            if spec.id == "project_root" {
                state.textValues[spec.id] = selection.path
            }
            if spec.id == "selected_path" {
                state.textValues[spec.id] = selection.path
            }
            if spec.id == "selected_readme_path" {
                state.textValues[spec.id] = selection.readmePath ?? ""
            }
            if spec.id == "project" {
                state.textValues[spec.id] = selection.path
            }
        }
    }

    private func loadRuns() -> [WorkflowRun] {
        let runsRoot = supportDirectory().appendingPathComponent("runs", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: runsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let manifests = items.compactMap { item -> WorkflowRun? in
            let manifestURL = item.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(WorkflowRunManifest.self, from: data) else {
                return nil
            }
            return WorkflowRun(
                id: manifest.id,
                workflowID: manifest.workflowID,
                workflowLabel: manifest.workflowLabel,
                startedAt: manifest.startedAt,
                finishedAt: manifest.finishedAt,
                exitCode: manifest.exitCode,
                commandPreview: manifest.commandPreview,
                workingDirectory: manifest.workingDirectory,
                stdoutPath: manifest.stdoutPath,
                stderrPath: manifest.stderrPath,
                manifestPath: manifest.manifestPath,
                artifactPaths: manifest.artifactPaths,
                selectionPath: manifest.selectionPath
            )
        }

        return manifests.sorted { $0.startedAt > $1.startedAt }
    }

    private func loadRunOutput(for id: String) -> String {
        guard let run = runs.first(where: { $0.id == id }) else { return "" }
        let stdout = (try? String(contentsOfFile: run.stdoutPath, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOfFile: run.stderrPath, encoding: .utf8)) ?? ""
        let combined = [stdout.isEmpty ? nil : "STDOUT\n\(stdout)", stderr.isEmpty ? nil : "STDERR\n\(stderr)"]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        return combined.isEmpty ? "No output captured." : combined
    }

    private func supportDirectory() -> URL {
        appSupportDirectory
    }

    private func logDiagnostics(_ message: String) {
        AppDebugLog.record(
            "[jwh] \(message)",
            enabled: isDiagnosticsLoggingEnabled,
            supportDirectory: supportDirectory()
        )
    }

    private func finishWorkflowRun(
        workflow: WorkflowDefinition,
        run: WorkflowRun,
        scaffoldContext: ScaffoldCompletionContext?
    ) {
        if workflow.isWriteAction {
            reloadAll()
        } else {
            runs.insert(run, at: 0)
        }

        defer {
            isRunning = false
        }

        logDiagnostics("workflow-finished id=\(workflow.id) exitCode=\(run.exitCode)")

        if workflow.id == "scaffold-project", run.exitCode == 0, let scaffoldContext {
            let stagedImportSucceeded = completeScaffoldProject(using: scaffoldContext)
            if scaffoldContext.hasStagedDocuments {
                let count = scaffoldContext.stagedDocuments.count
                statusMessage = stagedImportSucceeded
                    ? "Project created. Imported \(count) staged \(count == 1 ? "item" : "items") into docs."
                    : "Project created, but staged documents could not be imported"
            } else {
                statusMessage = scaffoldContext.sourceMaterialChoice == .now
                    ? "Project created. Add documents now."
                    : "Created project"
            }
            return
        }

        select(.run(run.id))
        statusMessage = "Finished with exit code \(run.exitCode)"
        if workflow.id == "scaffold-project", run.exitCode != 0 {
            activeAlert = AppAlert(
                title: "Project creation failed",
                message: "The scaffold script exited with code \(run.exitCode). Open the latest run output for details."
            )
        }
    }

    private func completeScaffoldProject(using context: ScaffoldCompletionContext) -> Bool {
        presentScaffoldPostCreate(
            mode: .created,
            projectTitle: context.projectTitle,
            projectRoot: context.projectRoot,
            readmePath: context.readmePath,
            sourceMaterialChoice: context.sourceMaterialChoice,
            shouldAutoPromptForDocuments: context.sourceMaterialChoice == .now && !context.hasStagedDocuments
        )

        defer {
            try? cleanupScaffoldWizardStaging(at: context.stagedDocumentDirectoryPath)
        }

        guard context.hasStagedDocuments else { return true }

        do {
            try importStagedDocumentsIntoScaffoldProject(context.stagedDocuments)
            return true
        } catch {
            activeAlert = AppAlert(title: "Could not import staged documents", message: error.localizedDescription)
            return false
        }
    }

    private func presentScaffoldPostCreate(
        mode: ScaffoldPostCreateMode,
        projectTitle: String,
        projectRoot: String,
        readmePath: String,
        sourceMaterialChoice: ScaffoldSourceMaterialChoice,
        shouldAutoPromptForDocuments: Bool
    ) {
        let postCreateState = ScaffoldPostCreateState(
            id: projectRoot,
            mode: mode,
            projectTitle: projectTitle,
            projectRoot: projectRoot,
            readmePath: readmePath,
            sourceMaterialChoice: sourceMaterialChoice,
            shouldAutoPromptForDocuments: shouldAutoPromptForDocuments,
            importedPaths: []
        )

        scaffoldProjectWizardDraft = ScaffoldProjectWizardDraft()
        scaffoldProjectWizardStep = .workingTitle
        scaffoldPostCreateState = postCreateState

        if let itemID = workspaceItemID(forPath: projectRoot) {
            select(.workspace(itemID))
        } else {
            select(.workflow("scaffold-project"))
        }
    }

    private func makeScaffoldCompletionContext(
        workflow: WorkflowDefinition,
        state: WorkflowParameterState,
        draft: ScaffoldProjectWizardDraft
    ) -> ScaffoldCompletionContext? {
        guard workflow.id == "scaffold-project",
              let sourceMaterialChoice = draft.sourceMaterialChoice else {
            return nil
        }

        let projectRoot = state.stringValue(for: "project_root").trimmingCharacters(in: .whitespacesAndNewlines)
        let projectTitle = state.stringValue(for: "title").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectRoot.isEmpty, !projectTitle.isEmpty else { return nil }

        return ScaffoldCompletionContext(
            projectTitle: projectTitle,
            projectRoot: projectRoot,
            readmePath: URL(fileURLWithPath: projectRoot)
                .appendingPathComponent("README.md")
                .path,
            sourceMaterialChoice: sourceMaterialChoice,
            stagedDocumentDirectoryPath: draft.stagedDocumentDirectoryPath,
            stagedDocuments: sourceMaterialChoice == .now ? draft.stagedDocuments : []
        )
    }

    private func workspaceItemID(forPath path: String) -> String? {
        workspaceQueries.items.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
                == URL(fileURLWithPath: path).standardizedFileURL.path
        })?.id
    }

    private func createLocalDraft(in projectURL: URL, projectTitle: String) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = projectURL.appendingPathComponent(DraftSupport.localDraftFilename(projectTitle: projectTitle))

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw NSError(
                domain: "JournalismWorkflowHub.DraftTemplate",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "A draft already exists at \(destinationURL.path)."]
            )
        }

        let draftData = try DraftSupport.scaffoldDraftData(projectTitle: projectTitle)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true, attributes: nil)
        try draftData.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func createPitchDocument(in projectURL: URL, projectTitle: String) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = projectURL.appendingPathComponent("Pitch.md")

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw NSError(
                domain: "JournalismWorkflowHub.PitchTemplate",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "A pitch already exists at \(destinationURL.path)."]
            )
        }

        let normalizedTitle = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let pitchBody = """
        # Pitch

        ## Working title

        \(normalizedTitle.isEmpty ? "Untitled project" : normalizedTitle)

        ## Core angle

        -

        ## Why now

        -

        ## Questions for the editor

        - What is the sharpest publishable angle?
        - What still needs reporting before this can move forward?
        """

        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true, attributes: nil)
        try pitchBody.write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }

    private func importDocuments(from urls: [URL], into docsURL: URL) throws -> [String] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
        var importedPaths: [String] = []

        for url in urls {
            let destination = uniqueImportDestinationURL(for: url, in: docsURL, fileManager: fileManager)
            try SecurityScopedAccess.withAccess(to: [url, docsURL]) {
                try fileManager.copyItem(at: url, to: destination)
            }
            importedPaths.append(destination.path)
        }

        return importedPaths
    }

    private func stageScaffoldWizardDocuments(from urls: [URL], into stagingDirectory: URL) throws -> [ScaffoldStagedDocument] {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true, attributes: nil)

        var stagedDocuments: [ScaffoldStagedDocument] = []
        for url in urls {
            let destination = uniqueImportDestinationURL(for: url, in: stagingDirectory, fileManager: fileManager)
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            try SecurityScopedAccess.withAccess(to: [url, stagingDirectory]) {
                try fileManager.copyItem(at: url, to: destination)
            }
            stagedDocuments.append(
                ScaffoldStagedDocument(
                    sourcePath: url.path,
                    stagedPath: destination.path,
                    isDirectory: isDirectory.boolValue
                )
            )
        }

        return stagedDocuments
    }

    private func importStagedDocumentsIntoScaffoldProject(_ documents: [ScaffoldStagedDocument]) throws {
        guard var state = scaffoldPostCreateState else { return }
        let stagedURLs = documents.map { URL(fileURLWithPath: $0.stagedPath) }
        let importedPaths = try importDocuments(from: stagedURLs, into: state.docsURL)
        state.importedPaths = Array(Set(state.importedPaths + importedPaths)).sorted()
        scaffoldPostCreateState = state
        reloadWorkspace()

        if let itemID = workspaceItemID(forPath: state.projectRoot) {
            select(.workspace(itemID))
        }
    }

    private func scaffoldWizardStagingDirectory(existingPath: String) throws -> URL {
        let fileManager = FileManager.default
        if !existingPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: existingPath)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return url
        }

        let root = supportDirectory().appendingPathComponent("scaffold_wizard_staging", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory
    }

    private func cleanupScaffoldWizardStaging(for draft: ScaffoldProjectWizardDraft) throws {
        guard !draft.stagedDocumentDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        try cleanupScaffoldWizardStaging(at: draft.stagedDocumentDirectoryPath)
    }

    private func cleanupScaffoldWizardStaging(at path: String) throws {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func cleanupScaffoldWizardStagingDirectoryIfNeeded(path: String, remainingCount: Int) {
        guard remainingCount == 0 else { return }
        try? cleanupScaffoldWizardStaging(at: path)
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func appendCaptureRecords(_ records: [CaptureRecord]) {
        captureRecords.append(contentsOf: records)
        captureRecords.sort { $0.capturedAt > $1.capturedAt }
        captureStore.replace(with: captureRecords)
    }

    private func removeCaptureRecord(_ id: String) {
        captureRecords.removeAll { $0.id == id }
        captureStore.replace(with: captureRecords)
    }

    private func mergedCaptureRecordsWithRecoveredItems(_ records: [CaptureRecord]) -> [CaptureRecord] {
        let existingRecordIDs = Set(records.map(\.id))
        let recoveredRecords = captureStore.recoverRecordsFromStorage(excluding: existingRecordIDs)
        guard !recoveredRecords.isEmpty else {
            return records.sorted { $0.capturedAt > $1.capturedAt }
        }

        return (records + recoveredRecords).sorted { $0.capturedAt > $1.capturedAt }
    }

    private func updateCaptureRecord(
        _ id: String,
        displayName: String? = nil,
        importedStoragePath: String? = nil,
        state: CaptureRecordState? = nil,
        failureDescription: String? = nil
    ) {
        guard let index = captureRecords.firstIndex(where: { $0.id == id }) else { return }
        let current = captureRecords[index]
        captureRecords[index] = CaptureRecord(
            id: current.id,
            displayName: displayName ?? current.displayName,
            originalSourcePath: current.originalSourcePath,
            importedStoragePath: importedStoragePath ?? current.importedStoragePath,
            capturedAt: current.capturedAt,
            captureType: current.captureType,
            state: state ?? current.state,
            failureDescription: failureDescription,
            userNote: current.userNote,
            assignedTargetPath: current.assignedTargetPath,
            assignedAt: current.assignedAt,
            assignedDestinationPath: current.assignedDestinationPath
        )
        captureRecords.sort { $0.capturedAt > $1.capturedAt }
        captureStore.replace(with: captureRecords)
    }

    private func updateCaptureRecord(
        _ id: String,
        transform: (CaptureRecord) -> CaptureRecord
    ) {
        guard let index = captureRecords.firstIndex(where: { $0.id == id }) else { return }
        captureRecords[index] = transform(captureRecords[index])
        captureRecords.sort { $0.capturedAt > $1.capturedAt }
        captureStore.replace(with: captureRecords)
    }

    private func captureRecordType(for sourceURL: URL) -> CaptureRecordType {
        if (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return .folder
        }
        return .file
    }

    private func copyCaptureItemToStorage(for record: CaptureRecord) async throws -> URL {
        guard let originalSourcePath = record.originalSourcePath else {
            throw NSError(
                domain: "JournalismWorkflowHub.Capture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No source path was recorded for this capture item."]
            )
        }

        let sourceURL = URL(fileURLWithPath: originalSourcePath).standardizedFileURL
        let destinationDirectory = captureStore.storageDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent(record.id, isDirectory: true)

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try SecurityScopedAccess.withAccess(to: [sourceURL, destinationDirectory]) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            return destinationURL
        }.value
    }

    private func summarizeImportedDocsOverview(
        projectRoot: String,
        importedPaths: [String],
        relevanceNote: String? = nil,
        reviewNotesByPath: [String: String] = [:]
    ) async throws {
        guard let scriptPath = bundledKnowledgeOpsScriptPath("summarize_scaffold_docs.py") else {
            throw NSError(
                domain: "JournalismWorkflowHub.ScaffoldSummary",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The bundled scaffold summary script is missing from the app build."]
            )
        }

        let environment = ProcessInfo.processInfo.environment
        let pythonExecutable = try CommandRunner.resolveExecutableURL(for: "python3", environment: environment)
        let workspaceRoot = self.workspaceRoot
        let importedPaths = importedPaths.sorted()
        let reviewNotesByPath = reviewNotesByPath
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = pythonExecutable
            var arguments = [scriptPath, "--project-root", projectRoot]
                + importedPaths.flatMap { ["--imported-path", $0] }
                + (relevanceNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { ["--relevance-note", $0] } ?? [])

            let reviewNotesURL: URL?
            if reviewNotesByPath.isEmpty {
                reviewNotesURL = nil
            } else {
                let payload = try JSONSerialization.data(withJSONObject: reviewNotesByPath, options: [.prettyPrinted, .sortedKeys])
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("jwh-review-notes-\(UUID().uuidString).json")
                try payload.write(to: tempURL)
                reviewNotesURL = tempURL
                arguments += ["--review-notes-file", tempURL.path]
            }

            process.arguments = arguments
            process.currentDirectoryURL = workspaceRoot
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let reviewNotesURL {
                try? FileManager.default.removeItem(at: reviewNotesURL)
            }
            let stdoutText = String(data: stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                let message = !stderrText.isEmpty
                    ? stderrText
                    : (!stdoutText.isEmpty ? stdoutText : "The local summarization step failed.")
                throw NSError(
                    domain: "JournalismWorkflowHub.ScaffoldSummary",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
        }.value
    }

    private func writeQuickCaptureNote(
        recordID: String,
        displayName: String,
        text: String,
        capturedAt: Date
    ) async throws -> URL {
        let filename = captureQuickNoteFilename(from: displayName, capturedAt: capturedAt)
        let destinationDirectory = captureStore.storageDirectory
            .appendingPathComponent("items", isDirectory: true)
            .appendingPathComponent(recordID, isDirectory: true)

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true, attributes: nil)
            let destinationURL = destinationDirectory.appendingPathComponent(filename)
            try text.write(to: destinationURL, atomically: true, encoding: .utf8)
            return destinationURL
        }.value
    }

    private func copyCaptureRecord(from sourceURL: URL, into docsURL: URL) async throws -> URL {
        let normalizedSource = sourceURL.standardizedFileURL
        let normalizedDocs = docsURL.standardizedFileURL

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: normalizedDocs, withIntermediateDirectories: true, attributes: nil)
            let destinationURL = uniqueImportDestinationURL(for: normalizedSource, in: normalizedDocs, fileManager: fileManager)
            try SecurityScopedAccess.withAccess(to: [normalizedSource, normalizedDocs]) {
                try fileManager.copyItem(at: normalizedSource, to: destinationURL)
            }
            return destinationURL
        }.value
    }

    private func appendReviewNoteToFactsFileIfNeeded(
        note: String,
        sourceDisplayName: String,
        assignedDestinationPath: String,
        projectRoot: URL
    ) throws -> Bool {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedNote.isEmpty else { return false }

        let docsURL = projectRoot.appendingPathComponent("docs", isDirectory: true)
        let factsURL = docsURL.appendingPathComponent("facts.md")
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)

        let existingText = (try? String(contentsOf: factsURL, encoding: .utf8)) ?? ""
        let header = "# Facts\n\n"
        var updatedText = existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? header : existingText
        if !updatedText.hasSuffix("\n") {
            updatedText += "\n"
        }
        if !updatedText.hasSuffix("\n\n") {
            updatedText += "\n"
        }

        updatedText += factsEntry(
            note: normalizedNote,
            sourceDisplayName: sourceDisplayName,
            assignedDestinationPath: assignedDestinationPath,
            docsRootPath: docsURL.path
        )
        try updatedText.write(to: factsURL, atomically: true, encoding: .utf8)
        return true
    }

    private func moveCaptureRecord(from sourceURL: URL, into destinationRoot: URL) async throws -> URL {
        let normalizedSource = sourceURL.standardizedFileURL
        let normalizedDestinationRoot = destinationRoot.standardizedFileURL

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: normalizedDestinationRoot, withIntermediateDirectories: true, attributes: nil)
            let destinationURL = uniqueImportDestinationURL(for: normalizedSource, in: normalizedDestinationRoot, fileManager: fileManager)
            try fileManager.moveItem(at: normalizedSource, to: destinationURL)
            return destinationURL
        }.value
    }

    private func deleteCaptureRecordPayload(at sourceURL: URL) async throws {
        let normalizedSource = sourceURL.standardizedFileURL

        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: normalizedSource.path) {
                try fileManager.removeItem(at: normalizedSource)
            }
        }.value
    }

    private func cleanupCaptureContainer(afterRemoving sourceURL: URL) {
        let containerURL = sourceURL.standardizedFileURL.deletingLastPathComponent()
        guard containerURL.lastPathComponent.count == 36 else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        guard contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: containerURL)
    }

    private func configuration(for draft: OnboardingDraft) throws -> AppConfiguration {
        switch draft.startMode {
        case .demo:
            guard let demoWorkspaceRoot else {
                throw NSError(
                    domain: "JournalismWorkflowHub.Onboarding",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The bundled demo workspace is not available."]
                )
            }
            return AppConfiguration(
                profile: .standalone,
                workspaceRoot: demoWorkspaceRoot,
                demoWorkspaceRoot: demoWorkspaceRoot
            )
        case .existingWorkspace, .createWorkspace:
            let trimmedPath = draft.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                throw NSError(
                    domain: "JournalismWorkflowHub.Onboarding",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Choose a workspace folder before continuing."]
                )
            }
            return AppConfiguration(
                profile: .standard,
                workspaceRoot: URL(fileURLWithPath: trimmedPath).standardizedFileURL,
                demoWorkspaceRoot: demoWorkspaceRoot
            )
        }
    }

    private func applyConfiguration(_ configuration: AppConfiguration) {
        appProfile = configuration.profile
        workspaceRoot = configuration.workspaceRoot
        demoWorkspaceRoot = configuration.demoWorkspaceRoot
        scanner = WorkspaceScanner(workspaceRoot: configuration.workspaceRoot)
        catalog = WorkspaceCatalogStore(workspaceRoot: configuration.workspaceRoot)
        captureStore = CaptureStore(workspaceRoot: configuration.workspaceRoot)
        maintenanceStore = MaintenanceStore(workspaceRoot: configuration.workspaceRoot)
        workspaceQueries = .empty
        runner = CommandRunner(workspaceRoot: configuration.workspaceRoot, appProfile: configuration.profile)
        WorkspaceRootResolver.persistProfile(configuration.profile)
        if configuration.profile == .standard {
            WorkspaceRootResolver.persist(configuration.workspaceRoot)
        }
        backHistory.removeAll()
        forwardHistory.removeAll()
        updateNavigationAvailability()
        reloadAll()
    }

    private func updateProjectState(
        _ projectState: ProjectState,
        for item: WorkspaceItem,
        compatibilityStatusOverride: ProjectLifecycleStatus? = nil
    ) {
        updateProjectMetadata(
            title: item.frontmatter["project"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? item.title,
            projectType: item.projectType,
            projectState,
            dossierSlug: item.dossierSlug,
            isInDailyFocus: item.isInDailyFocus,
            for: item,
            compatibilityStatusOverride: compatibilityStatusOverride
        )
    }

    private func updateProjectDailyFocus(_ isInDailyFocus: Bool, for item: WorkspaceItem) {
        let projectState = item.projectState ?? ProjectState(
            activityState: .active,
            workflowStage: .activeInvestigation,
            inactiveReason: nil
        )
        let compatibilityStatus = item.compatibilityStatus
            ?? projectState.legacyLifecycleStatus(isArchivedStorage: item.section == .archives)
        updateProjectMetadata(
            title: item.frontmatter["project"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? item.title,
            projectType: item.projectType,
            projectState,
            dossierSlug: item.dossierSlug,
            isInDailyFocus: isInDailyFocus,
            for: item,
            compatibilityStatusOverride: compatibilityStatus
        )
    }

    private func updateProjectMetadata(
        title: String,
        projectType: WorkspaceProjectType,
        _ projectState: ProjectState,
        dossierSlug: String?,
        isInDailyFocus: Bool,
        for item: WorkspaceItem,
        compatibilityStatusOverride: ProjectLifecycleStatus? = nil
    ) {
        guard let readmePath = item.readmePath else {
            activeAlert = AppAlert(
                title: "Missing README",
                message: "This project does not have a root README.md to update."
            )
            return
        }

        do {
            let readmeURL = URL(fileURLWithPath: readmePath)
            let currentText = try String(contentsOf: readmeURL, encoding: .utf8)
            let normalizedDossierSlug = dossierSlug?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let updatedText = updateFrontmatter(in: currentText) { frontmatter, orderedKeys in
                applyProjectIdentityFrontmatter(
                    title: title,
                    projectType: projectType,
                    to: &frontmatter,
                    orderedKeys: &orderedKeys
                )
                let compatibilityStatus = compatibilityStatusOverride
                    ?? projectState.legacyLifecycleStatus(isArchivedStorage: item.section == .archives)
                applyProjectStateFrontmatter(
                    projectState,
                    compatibilityStatus: compatibilityStatus,
                    to: &frontmatter,
                    orderedKeys: &orderedKeys
                )
                applyDailyFocusFrontmatter(
                    isInDailyFocus,
                    to: &frontmatter,
                    orderedKeys: &orderedKeys
                )
                if let normalizedDossierSlug {
                    frontmatter["dossier"] = normalizedDossierSlug
                    if !orderedKeys.contains("dossier") {
                        orderedKeys.append("dossier")
                    }
                } else {
                    frontmatter.removeValue(forKey: "dossier")
                }
            }
            try updatedText.write(to: readmeURL, atomically: true, encoding: .utf8)
            reloadWorkspace()
            let focusSummary = isInDailyFocus ? "in daily focus" : "out of daily focus"
            statusMessage = "\(title) updated to \(projectState.detailLabel.lowercased()) and \(focusSummary)"
        } catch {
            activeAlert = AppAlert(
                title: "Could not update project details",
                message: error.localizedDescription
            )
            statusMessage = error.localizedDescription
        }
    }

    private func updateCanonicalWorkingDocumentPath(
        _ relativePath: String?,
        role: WorkspaceDocumentRole,
        for item: WorkspaceItem,
        successMessage: String
    ) {
        guard let key = canonicalWorkingDocumentFrontmatterKey(for: role) else {
            activeAlert = AppAlert(
                title: "Unsupported document role",
                message: "Only draft and pitch can be assigned from this screen right now."
            )
            return
        }

        guard let readmePath = item.readmePath else {
            activeAlert = AppAlert(
                title: "Missing README",
                message: "This project does not have a root README.md to update."
            )
            return
        }

        let normalizedPath = relativePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        do {
            let readmeURL = URL(fileURLWithPath: readmePath)
            let currentText = try String(contentsOf: readmeURL, encoding: .utf8)
            let updatedText = updateFrontmatter(in: currentText) { frontmatter, orderedKeys in
                if let normalizedPath {
                    frontmatter[key] = normalizedPath
                    if !orderedKeys.contains(key) {
                        orderedKeys.append(key)
                    }
                } else {
                    frontmatter.removeValue(forKey: key)
                }
            }
            try updatedText.write(to: readmeURL, atomically: true, encoding: .utf8)
            reloadWorkspace()

            if let itemID = workspaceItemID(forPath: item.path) {
                select(.workspace(itemID))
            }

            statusMessage = successMessage
        } catch {
            activeAlert = AppAlert(
                title: "Could not update canonical \(role.label.lowercased())",
                message: error.localizedDescription
            )
            statusMessage = error.localizedDescription
        }
    }

    private func canonicalWorkingDocumentFrontmatterKey(for role: WorkspaceDocumentRole) -> String? {
        switch role {
        case .draft:
            return "canonical_draft"
        case .pitch:
            return "canonical_pitch"
        default:
            return nil
        }
    }

    private func quickProjectState(
        for targetStatus: ProjectLifecycleStatus,
        basedOn currentState: ProjectState
    ) -> ProjectState {
        switch targetStatus {
        case .active:
            return ProjectState(
                activityState: .active,
                workflowStage: currentState.workflowStage,
                inactiveReason: nil
            )
        case .onHold:
            return ProjectState(
                activityState: .inactive,
                workflowStage: currentState.workflowStage,
                inactiveReason: .waiting
            )
        case .done, .archived:
            return ProjectState(
                activityState: .inactive,
                workflowStage: currentState.workflowStage,
                inactiveReason: .finished
            )
        }
    }

    private func archiveYear(for item: WorkspaceItem) -> String {
        let components = URL(fileURLWithPath: item.path).standardizedFileURL.pathComponents
        if let projectsIndex = components.firstIndex(of: "Projects"), components.indices.contains(projectsIndex + 1) {
            let candidate = components[projectsIndex + 1]
            if candidate.count == 4, Int(candidate) != nil {
                return candidate
            }
        }
        if let started = item.frontmatter["started"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           started.count >= 4 {
            let candidate = String(started.prefix(4))
            if Int(candidate) != nil {
                return candidate
            }
        }
        return String(Calendar(identifier: .gregorian).component(.year, from: .now))
    }

    private func applyProjectOffboarding(
        state: ProjectStatusChangeState,
        outcome: ProjectOffboardingOutcome,
        publishedPDFURL: URL?,
        routeToDossier: Bool,
        producedSummary: String,
        remainingOpenSummary: String,
        impactSummary: String
    ) async throws -> ProjectOffboardingResult? {
        let projectURL = URL(fileURLWithPath: state.projectPath)
        let readmeURL = URL(fileURLWithPath: state.readmePath)
        let docsURL = projectURL.appendingPathComponent("docs", isDirectory: true)
        let trimmedProducedSummary = producedSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemainingOpenSummary = remainingOpenSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImpactSummary = impactSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        var importedPDFPath: String?
        if let publishedPDFURL {
            let importedPaths = try copyDocuments([publishedPDFURL], into: docsURL)
            importedPDFPath = importedPaths.first
        }

        let currentText = try String(contentsOf: readmeURL, encoding: .utf8)
        guard let finalProjectState = outcome.resultingProjectState(from: state.currentProjectState) else {
            throw NSError(
                domain: "JournalismWorkflowHub.ProjectOffboarding",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Choose an explicit offboarding outcome before saving closeout."]
            )
        }

        var updatedMaintenanceItems = maintenanceStore.load()
        updatedMaintenanceItems.removeAll {
            $0.source == "project_offboarding"
                && $0.projectPath == state.projectPath
        }

        if outcome.deletesProject {
            try deleteProjectDirectory(at: projectURL)
            maintenanceStore.replace(with: updatedMaintenanceItems)
            return ProjectOffboardingResult(
                importedPDFPath: nil,
                finalProjectPath: nil,
                maintenanceItemCount: 0,
                deletedProject: true
            )
        }

        let managedSection = buildProjectCloseoutSection(
            compatibilityStatus: state.targetCompatibilityStatus,
            projectState: finalProjectState,
            outcome: outcome,
            projectRoot: projectURL,
            importedPDFPath: importedPDFPath,
            producedSummary: trimmedProducedSummary,
            remainingOpenSummary: trimmedRemainingOpenSummary,
            impactSummary: trimmedImpactSummary
        )

        let updatedText = updateFrontmatter(in: currentText) { frontmatter, orderedKeys in
            applyProjectStateFrontmatter(
                finalProjectState,
                compatibilityStatus: state.targetCompatibilityStatus,
                to: &frontmatter,
                orderedKeys: &orderedKeys
            )
        }
        let finalText = upsertingManagedSection(
            in: updatedText,
            startMarker: projectCloseoutSectionStart,
            endMarker: projectCloseoutSectionEnd,
            sectionBody: managedSection
        )

        try finalText.write(to: readmeURL, atomically: true, encoding: .utf8)

        var finalProjectURL = projectURL
        if state.targetCompatibilityStatus == .archived {
            let archiveDestination = archiveDestinationURL(
                for: projectURL,
                year: state.archiveYear,
                projectType: state.projectType,
                outcome: outcome,
                workspaceRoot: workspaceRoot
            )
            try moveProjectDirectory(from: projectURL, to: archiveDestination)
            finalProjectURL = archiveDestination
            if let existingImportedPDFPath = importedPDFPath {
                importedPDFPath = finalProjectURL
                    .appendingPathComponent("docs", isDirectory: true)
                    .appendingPathComponent(URL(fileURLWithPath: existingImportedPDFPath).lastPathComponent)
                    .path
            }
        }

        updatedMaintenanceItems.removeAll {
            $0.source == "project_offboarding"
                && $0.projectPath == finalProjectURL.path
        }

        if routeToDossier, let dossierURL = dossierURL(for: state.dossierSlug, workspaceRoot: workspaceRoot) {
            try writeDossierHandoffNote(
                to: dossierURL,
                projectTitle: state.projectTitle,
                projectURL: finalProjectURL,
                compatibilityStatus: state.targetCompatibilityStatus,
                projectState: finalProjectState,
                outcome: outcome,
                importedPDFPath: importedPDFPath,
                producedSummary: trimmedProducedSummary,
                remainingOpenSummary: trimmedRemainingOpenSummary,
                impactSummary: trimmedImpactSummary
            )
        } else if routeToDossier, state.dossierSlug != nil {
            updatedMaintenanceItems.append(
                makeMaintenanceItem(
                    kind: .missingDossierHandoff,
                    projectTitle: state.projectTitle,
                    projectPath: finalProjectURL.path,
                    detail: "The project links to dossier `\(state.dossierSlug ?? "")`, but no dossier folder was found for a durable closeout handoff."
                )
            )
        }

        updatedMaintenanceItems.append(contentsOf: maintenanceItemsForOffboarding(
            state: state,
            outcome: outcome,
            finalProjectPath: finalProjectURL.path,
            publishedPDFImported: importedPDFPath != nil,
            routeToDossier: routeToDossier,
            producedSummary: trimmedProducedSummary,
            remainingOpenSummary: trimmedRemainingOpenSummary,
            impactSummary: trimmedImpactSummary
        ))
        maintenanceStore.replace(with: updatedMaintenanceItems)

        return ProjectOffboardingResult(
            importedPDFPath: importedPDFPath,
            finalProjectPath: finalProjectURL.path,
            maintenanceItemCount: updatedMaintenanceItems.filter {
                $0.source == "project_offboarding" && $0.projectPath == finalProjectURL.path
            }.count,
            deletedProject: false
        )
    }
}

private func captureQuickNoteTitle(from text: String) -> String {
    let firstLine = text
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? "Quick note"

    return String(firstLine.prefix(72))
}

private func captureQuickNoteFilename(from displayName: String, capturedAt: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HHmmss"
    let timestamp = formatter.string(from: capturedAt)
    let base = sanitizedCaptureFilename(displayName)
    return base.isEmpty ? "quick_note_\(timestamp).md" : "\(base)_\(timestamp).md"
}

private func sanitizedCaptureFilename(_ text: String) -> String {
    let lowered = text.lowercased()
    let replaced = lowered.replacingOccurrences(
        of: #"[^a-z0-9]+"#,
        with: "_",
        options: .regularExpression
    )
    return replaced
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        .prefix(48)
        .description
}

private func uniqueImportDestinationURL(for sourceURL: URL, in docsURL: URL, fileManager: FileManager = .default) -> URL {
    let initialDestination = docsURL.appendingPathComponent(sourceURL.lastPathComponent)
    guard fileManager.fileExists(atPath: initialDestination.path) else {
        return initialDestination
    }

    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    var suffix = 2

    while true {
        let candidateName = pathExtension.isEmpty
            ? "\(baseName)_\(suffix)"
            : "\(baseName)_\(suffix).\(pathExtension)"
        let candidate = docsURL.appendingPathComponent(candidateName)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        suffix += 1
    }
}

private struct ScaffoldCompletionContext {
    let projectTitle: String
    let projectRoot: String
    let readmePath: String
    let sourceMaterialChoice: ScaffoldSourceMaterialChoice
    let stagedDocumentDirectoryPath: String
    let stagedDocuments: [ScaffoldStagedDocument]

    var hasStagedDocuments: Bool {
        !stagedDocuments.isEmpty
    }
}

struct AppAlert: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ParsedReadmeDocument {
    var frontmatter: [String: String]
    var orderedKeys: [String]
    var body: String
}

private struct ProjectOffboardingResult {
    let importedPDFPath: String?
    let finalProjectPath: String?
    let maintenanceItemCount: Int
    let deletedProject: Bool
}

private let projectCloseoutSectionStart = "<!-- project_closeout:start -->"
private let projectCloseoutSectionEnd = "<!-- project_closeout:end -->"

private func parseReadmeDocument(_ text: String) -> ParsedReadmeDocument {
    let lines = text.components(separatedBy: .newlines)
    guard let firstLine = lines.first,
          firstLine.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
        return ParsedReadmeDocument(frontmatter: [:], orderedKeys: [], body: text)
    }

    var frontmatter: [String: String] = [:]
    var orderedKeys: [String] = []
    var endIndex: Int?

    for index in 1..<lines.count {
        if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
            endIndex = index
            break
        }

        guard let colon = lines[index].firstIndex(of: ":") else { continue }
        let key = String(lines[index][..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(lines[index][lines[index].index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        frontmatter[key] = value
        if !orderedKeys.contains(key) {
            orderedKeys.append(key)
        }
    }

    guard let endIndex else {
        return ParsedReadmeDocument(frontmatter: [:], orderedKeys: [], body: text)
    }

    let body = lines.dropFirst(endIndex + 1).joined(separator: "\n")
    return ParsedReadmeDocument(frontmatter: frontmatter, orderedKeys: orderedKeys, body: body)
}

private func updateFrontmatter(
    in text: String,
    mutate: (inout [String: String], inout [String]) -> Void
) -> String {
    var document = parseReadmeDocument(text)
    mutate(&document.frontmatter, &document.orderedKeys)

    let orderedKeys = document.orderedKeys + document.frontmatter.keys.filter { !document.orderedKeys.contains($0) }.sorted()
    var lines = ["---"]
    for key in orderedKeys {
        guard let value = document.frontmatter[key] else { continue }
        lines.append("\(key): \(value)")
    }
    lines.append("---")

    let frontmatterText = lines.joined(separator: "\n")
    if document.body.isEmpty {
        return frontmatterText + "\n"
    }
    return frontmatterText + "\n" + document.body
}

private func upsertingManagedSection(
    in text: String,
    startMarker: String,
    endMarker: String,
    sectionBody: String
) -> String {
    if let startRange = text.range(of: startMarker),
       let endRange = text.range(of: endMarker, range: startRange.upperBound..<text.endIndex) {
        let replacementRange = startRange.lowerBound..<endRange.upperBound
        return text.replacingCharacters(in: replacementRange, with: sectionBody)
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return sectionBody + "\n"
    }
    return trimmed + "\n\n" + sectionBody + "\n"
}

private func buildProjectCloseoutSection(
    compatibilityStatus: ProjectLifecycleStatus,
    projectState: ProjectState,
    outcome: ProjectOffboardingOutcome,
    projectRoot: URL,
    importedPDFPath: String?,
    producedSummary: String,
    remainingOpenSummary: String,
    impactSummary: String
) -> String {
    var lines = [projectCloseoutSectionStart, "## Project Closeout", ""]
    lines.append("- Closed on: `\(currentISODateString())`")
    lines.append("- Activity state: `\(projectState.activityState.rawValue)`")
    lines.append("- Workflow stage: `\(projectState.workflowStage.rawValue)`")
    if let inactiveReason = projectState.inactiveReason {
        lines.append("- Inactive reason: `\(inactiveReason.rawValue)`")
    }
    lines.append("- Outcome: `\(outcome.rawValue)`")
    lines.append("- Workspace action: \(workspaceActionSummary(for: compatibilityStatus))")
    lines.append("- Compatibility status: `\(compatibilityStatus.rawValue)`")

    if let importedPDFPath {
        lines.append("- Published PDF: `\(relativePath(importedPDFPath, from: projectRoot.path))`")
    }
    if !producedSummary.isEmpty {
        lines.append("- What it produced: \(producedSummary)")
    }
    if !remainingOpenSummary.isEmpty {
        lines.append("- What remains open: \(remainingOpenSummary)")
    }
    if !impactSummary.isEmpty {
        lines.append("- Impact / follow-up: \(impactSummary)")
    }

    lines.append("")
    lines.append(projectCloseoutSectionEnd)
    return lines.joined(separator: "\n")
}

private func workspaceActionSummary(for status: ProjectLifecycleStatus) -> String {
    switch status {
    case .archived:
        return "Move project folder into Archives"
    case .done:
        return "Keep project folder in Projects"
    case .active:
        return "Keep project active"
    case .onHold:
        return "Keep project inactive in Projects"
    }
}

private func deleteProjectDirectory(at projectURL: URL) throws {
    try FileManager.default.removeItem(at: projectURL)
}

private func applyProjectIdentityFrontmatter(
    title: String,
    projectType: WorkspaceProjectType,
    to frontmatter: inout [String: String],
    orderedKeys: inout [String]
) {
    frontmatter["project"] = title
    frontmatter["project_type"] = projectType.rawValue

    for key in ["project", "project_type"] where !orderedKeys.contains(key) {
        orderedKeys.append(key)
    }
}

private func applyProjectStateFrontmatter(
    _ projectState: ProjectState,
    compatibilityStatus: ProjectLifecycleStatus,
    to frontmatter: inout [String: String],
    orderedKeys: inout [String]
) {
    frontmatter["activity_state"] = projectState.activityState.rawValue
    frontmatter["workflow_stage"] = projectState.workflowStage.rawValue
    if let inactiveReason = projectState.inactiveReason, projectState.activityState == .inactive {
        frontmatter["inactive_reason"] = inactiveReason.rawValue
    } else {
        frontmatter.removeValue(forKey: "inactive_reason")
    }
    frontmatter["status"] = compatibilityStatus.rawValue

    for key in ["activity_state", "workflow_stage", "inactive_reason", "status"] where !orderedKeys.contains(key) {
        orderedKeys.append(key)
    }
}

private func applyDailyFocusFrontmatter(
    _ isInDailyFocus: Bool,
    to frontmatter: inout [String: String],
    orderedKeys: inout [String]
) {
    if isInDailyFocus {
        frontmatter["daily_focus"] = "true"
        if !orderedKeys.contains("daily_focus") {
            orderedKeys.append("daily_focus")
        }
    } else {
        frontmatter.removeValue(forKey: "daily_focus")
    }
}

private func currentISODateString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

private func relativePath(_ path: String, from rootPath: String) -> String {
    let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let normalizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
    guard normalizedPath.hasPrefix(normalizedRoot + "/") else {
        return normalizedPath
    }
    return String(normalizedPath.dropFirst(normalizedRoot.count + 1))
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private func copyDocuments(_ urls: [URL], into docsURL: URL) throws -> [String] {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
    var importedPaths: [String] = []

    for url in urls {
        let destination = uniqueImportDestinationURL(
            for: url.standardizedFileURL,
            in: docsURL.standardizedFileURL,
            fileManager: fileManager
        )
        try SecurityScopedAccess.withAccess(to: [url, docsURL]) {
            try fileManager.copyItem(at: url, to: destination)
        }
        importedPaths.append(destination.path)
    }

    return importedPaths
}

private func factsEntry(
    note: String,
    sourceDisplayName: String,
    assignedDestinationPath: String,
    docsRootPath: String
) -> String {
    let title = factsEntryTitle(note: note, fallback: sourceDisplayName)
    let source = factsSourceDescription(
        assignedDestinationPath: assignedDestinationPath,
        docsRootPath: docsRootPath
    )

    return """
    ## \(title)
    Fact: \(note)
    Source: \(source)

    """
}

private func factsEntryTitle(note: String, fallback: String) -> String {
    let singleLine = note
        .components(separatedBy: .newlines)
        .joined(separator: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !singleLine.isEmpty else { return fallback }
    guard singleLine.count > 72 else { return singleLine }

    let prefix = String(singleLine.prefix(72))
    if let split = prefix.lastIndex(of: " "), split > prefix.startIndex {
        return String(prefix[..<split])
    }

    return prefix
}

private func factsSourceDescription(
    assignedDestinationPath: String,
    docsRootPath: String
) -> String {
    let relative = relativePath(assignedDestinationPath, from: docsRootPath)
    if relative != assignedDestinationPath {
        return relative
    }

    return URL(fileURLWithPath: assignedDestinationPath).lastPathComponent
}

private func archiveDestinationURL(
    for projectURL: URL,
    year: String,
    projectType: WorkspaceProjectType,
    outcome: ProjectOffboardingOutcome,
    workspaceRoot: URL
) -> URL {
    let archiveYearRoot = workspaceRoot
        .appendingPathComponent("Archives", isDirectory: true)
        .appendingPathComponent(year, isDirectory: true)

    let parentURL: URL
    if projectType == .tooling {
        parentURL = archiveYearRoot.appendingPathComponent("personal", isDirectory: true)
    } else if outcome == .unpublished || outcome == .superseded {
        parentURL = archiveYearRoot.appendingPathComponent("unpublished", isDirectory: true)
    } else {
        parentURL = archiveYearRoot
    }

    return uniqueDirectoryDestination(
        sourceURL: projectURL.standardizedFileURL,
        in: parentURL.standardizedFileURL,
        fileManager: .default
    )
}

private func uniqueDirectoryDestination(sourceURL: URL, in parentURL: URL, fileManager: FileManager) -> URL {
    let initialDestination = parentURL.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
    guard fileManager.fileExists(atPath: initialDestination.path) else {
        return initialDestination
    }

    var suffix = 2
    while true {
        let candidate = parentURL.appendingPathComponent("\(sourceURL.lastPathComponent)_\(suffix)", isDirectory: true)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        suffix += 1
    }
}

private func moveProjectDirectory(from sourceURL: URL, to destinationURL: URL) throws {
    try FileManager.default.createDirectory(
        at: destinationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
}

private func dossierURL(for slug: String?, workspaceRoot: URL) -> URL? {
    guard let slug, !slug.isEmpty else { return nil }
    let candidates = [
        workspaceRoot.appendingPathComponent("Areas", isDirectory: true).appendingPathComponent(slug, isDirectory: true),
        workspaceRoot.appendingPathComponent("Resources", isDirectory: true).appendingPathComponent(slug, isDirectory: true)
    ]

    for candidate in candidates {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
    }
    return nil
}

private func writeDossierHandoffNote(
    to dossierURL: URL,
    projectTitle: String,
    projectURL: URL,
    compatibilityStatus: ProjectLifecycleStatus,
    projectState: ProjectState,
    outcome: ProjectOffboardingOutcome,
    importedPDFPath: String?,
    producedSummary: String,
    remainingOpenSummary: String,
    impactSummary: String
) throws {
    let handoffDirectory = dossierURL
        .appendingPathComponent("docs", isDirectory: true)
        .appendingPathComponent("project_closeouts", isDirectory: true)
    try FileManager.default.createDirectory(at: handoffDirectory, withIntermediateDirectories: true, attributes: nil)

    let fileURL = handoffDirectory.appendingPathComponent("\(projectURL.lastPathComponent)_closeout.md")
    let note = buildDossierHandoffNote(
        dossierURL: dossierURL,
        projectTitle: projectTitle,
        projectURL: projectURL,
        compatibilityStatus: compatibilityStatus,
        projectState: projectState,
        outcome: outcome,
        importedPDFPath: importedPDFPath,
        producedSummary: producedSummary,
        remainingOpenSummary: remainingOpenSummary,
        impactSummary: impactSummary
    )
    try note.write(to: fileURL, atomically: true, encoding: .utf8)
}

private func buildDossierHandoffNote(
    dossierURL: URL,
    projectTitle: String,
    projectURL: URL,
    compatibilityStatus: ProjectLifecycleStatus,
    projectState: ProjectState,
    outcome: ProjectOffboardingOutcome,
    importedPDFPath: String?,
    producedSummary: String,
    remainingOpenSummary: String,
    impactSummary: String
) -> String {
    var lines = [
        "# \(projectTitle) closeout handoff",
        "",
        "- Added on: `\(currentISODateString())`",
        "- Project folder: `\(relativePath(projectURL.path, from: dossierURL.path))`",
        "- Activity state: `\(projectState.activityState.rawValue)`",
        "- Workflow stage: `\(projectState.workflowStage.rawValue)`",
        "- Outcome: `\(outcome.rawValue)`",
        "- Workspace action: \(workspaceActionSummary(for: compatibilityStatus))",
        "- Compatibility status: `\(compatibilityStatus.rawValue)`"
    ]

    if let inactiveReason = projectState.inactiveReason {
        lines.append("- Inactive reason: `\(inactiveReason.rawValue)`")
    }

    if let importedPDFPath {
        lines.append("- Published PDF: `\(relativePath(importedPDFPath, from: dossierURL.path))`")
    }
    if !producedSummary.isEmpty {
        lines.append("- What it produced: \(producedSummary)")
    }
    if !remainingOpenSummary.isEmpty {
        lines.append("- What remains open: \(remainingOpenSummary)")
    }
    if !impactSummary.isEmpty {
        lines.append("- Impact / follow-up: \(impactSummary)")
    }

    lines.append("")
    lines.append("Keep this note as the dossier-facing trace of what this project produced and what may still matter later.")
    return lines.joined(separator: "\n")
}

private func maintenanceItemsForOffboarding(
    state: ProjectStatusChangeState,
    outcome: ProjectOffboardingOutcome,
    finalProjectPath: String,
    publishedPDFImported: Bool,
    routeToDossier: Bool,
    producedSummary: String,
    remainingOpenSummary: String,
    impactSummary: String
) -> [MaintenanceItem] {
    var items: [MaintenanceItem] = []

    if outcome == .published && !publishedPDFImported {
        items.append(
            makeMaintenanceItem(
                kind: .missingPublishedPDF,
                projectTitle: state.projectTitle,
                projectPath: finalProjectPath,
                detail: "Add the canonical published PDF to this project's docs folder so publication handoff is complete."
            )
        )
    }
    if producedSummary.isEmpty {
        items.append(
            makeMaintenanceItem(
                kind: .missingProducedSummary,
                projectTitle: state.projectTitle,
                projectPath: finalProjectPath,
                detail: "Add a short note about what this project produced."
            )
        )
    }
    if remainingOpenSummary.isEmpty {
        items.append(
            makeMaintenanceItem(
                kind: .missingRemainingOpen,
                projectTitle: state.projectTitle,
                projectPath: finalProjectPath,
                detail: "Add the lingering questions or follow-up threads that remain open after closeout."
            )
        )
    }
    if impactSummary.isEmpty {
        items.append(
            makeMaintenanceItem(
                kind: .missingImpactSummary,
                projectTitle: state.projectTitle,
                projectPath: finalProjectPath,
                detail: "Add any impact or follow-up worth remembering, such as questions, reactions, or government response."
            )
        )
    }
    if state.dossierSlug != nil && !routeToDossier {
        items.append(
            makeMaintenanceItem(
                kind: .missingDossierHandoff,
                projectTitle: state.projectTitle,
                projectPath: finalProjectPath,
                detail: "This project links to dossier `\(state.dossierSlug ?? "")`, but closeout skipped the dossier handoff."
            )
        )
    }

    return items
}

private func makeMaintenanceItem(
    kind: MaintenanceItemKind,
    projectTitle: String,
    projectPath: String,
    detail: String
) -> MaintenanceItem {
    MaintenanceItem(
        id: "project_offboarding::\(kind.rawValue)::\(projectPath)",
        kind: kind,
        projectTitle: projectTitle,
        projectPath: projectPath,
        detail: detail,
        createdAt: .now,
        source: "project_offboarding"
    )
}
