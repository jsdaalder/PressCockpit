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
    @Published var isRunning: Bool = false
    @Published var selectedRunOutput: String = ""
    @Published private(set) var documentMode: OnboardingDocumentMode
    @Published var hasCompletedOnboarding: Bool
    @Published private(set) var captureRecords: [CaptureRecord] = []
    @Published var scaffoldProjectWizardDraft = ScaffoldProjectWizardDraft()
    @Published var scaffoldProjectWizardStep: ScaffoldProjectWizardStep = .workingTitle
    @Published var scaffoldPostCreateState: ScaffoldPostCreateState?
    @Published private(set) var isFinishingScaffoldPostCreate: Bool = false
    @Published private(set) var hiddenWorkflowCount: Int = 0
    @Published private(set) var workflowPreflightReports: [String: WorkflowPreflightReport] = [:]
    @Published private(set) var canNavigateBack: Bool = false
    @Published private(set) var canNavigateForward: Bool = false

    private var scanner: WorkspaceScanner
    private var catalog: any WorkspaceCataloging
    private var captureStore: any CapturePersisting
    private var workspaceQueries: WorkspaceQueryStore = .empty
    private var runner: CommandRunner
    private var backHistory: [SidebarSelection] = []
    private var forwardHistory: [SidebarSelection] = []

    init(
        configuration: AppConfiguration = AppDefaults.configuration,
        catalog: (any WorkspaceCataloging)? = nil,
        captureStore: (any CapturePersisting)? = nil
    ) {
        self.appProfile = configuration.profile
        self.workspaceRoot = configuration.workspaceRoot
        self.demoWorkspaceRoot = configuration.demoWorkspaceRoot
        self.documentMode = OnboardingPreferences.documentMode()
        self.hasCompletedOnboarding = OnboardingPreferences.hasCompleted()
        self.scanner = WorkspaceScanner(workspaceRoot: configuration.workspaceRoot)
        self.catalog = catalog ?? WorkspaceCatalogStore(workspaceRoot: configuration.workspaceRoot)
        self.captureStore = captureStore ?? CaptureStore(workspaceRoot: configuration.workspaceRoot)
        self.runner = CommandRunner(workspaceRoot: configuration.workspaceRoot, appProfile: configuration.profile)
        if configuration.profile == .standard {
            WorkspaceRootResolver.persist(configuration.workspaceRoot)
        }
        WorkspaceRootResolver.persistProfile(configuration.profile)
        reloadAll()
    }

    var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding
    }

    func reloadAll() {
        reloadWorkspaceQueryState()
        reloadCaptureState()
        reloadPlanning()
        reloadWorkflows()
        reloadRuns()
    }

    func reloadWorkspace() {
        reloadWorkspaceQueryState()
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

    var overviewActions: [OverviewActionSummary] {
        OverviewDeriver.suggestedActions(from: workspaceQueries.snapshot, runs: runs)
    }

    var overviewOperations: [OverviewOperationSummary] {
        OverviewDeriver.operationSummaries(from: workspaceQueries.snapshot, runs: runs)
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

    var captureAssignedRecords: [CaptureRecord] {
        captureRecords
            .filter { $0.state == .assigned }
            .sorted { lhs, rhs in
                let lhsDate = lhs.assignedAt ?? lhs.capturedAt
                let rhsDate = rhs.assignedAt ?? rhs.capturedAt
                return lhsDate > rhsDate
            }
    }

    var captureAssignableProjects: [WorkspaceItem] {
        workspaceQueries.items
            .filter(\.isProjectRoot)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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

        isRunning = true
        statusMessage = "Running \(workflow.label)…"
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
        OnboardingPreferences.persist(draft: draft)
        documentMode = draft.documentMode
        hasCompletedOnboarding = true
        statusMessage = "Workspace ready"

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

    func reopenOnboarding() {
        hasCompletedOnboarding = false
        OnboardingPreferences.reset()
    }

    func refreshSelectedRun() {
        guard case .run(let id) = selection else { return }
        selectedRunOutput = loadRunOutput(for: id)
    }

    func openFolder(for item: WorkspaceItem?) {
        guard let item else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func openReadme(for item: WorkspaceItem?) {
        guard let item, let readmeURL = item.readmeURL else { return }
        NSWorkspace.shared.open(readmeURL)
    }

    func openPath(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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

    func openDocumentCache(_ document: WorkspaceDocument) {
        guard let cacheURL = document.cacheURL else { return }
        openURL(cacheURL)
    }

    func openProjectRoot(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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
            try await summarizeScaffoldDocsOverview(for: state)
            reloadWorkspace()
            statusMessage = "Updated docs overview from imported materials"
            scaffoldPostCreateState = nil
        } catch {
            statusMessage = error.localizedDescription
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

        presentScaffoldPostCreate(
            mode: .reused,
            projectTitle: projectTitle,
            projectRoot: projectRoot,
            readmePath: readmePath,
            sourceMaterialChoice: sourceMaterialChoice
        )

        statusMessage = sourceMaterialChoice == .now
            ? "Using existing project. Add documents now."
            : "Using existing project"
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
            let templateURL = try resolveDraftTemplateURL()
            let destinationURL = try createLocalDraft(
                from: templateURL,
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

    func shouldOfferGoogleDraftPromotion(for item: WorkspaceItem?) -> Bool {
        guard let item, item.isProjectRoot else { return false }
        if item.canonicalDraftDocument?.provider == .googleDocPointer {
            return false
        }
        return documentMode == .googleDocs || item.googleDriveURL != nil
    }

    func promoteGoogleDraft(for item: WorkspaceItem?) {
        guard let item, item.isProjectRoot else { return }

        let alert = NSAlert()
        alert.messageText = "Promote Google draft"
        alert.informativeText = "Paste the Google Docs URL or document ID. The app will write a root `.gdoc` pointer and use that Google Doc as the canonical draft target."
        alert.alertStyle = .informational

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        inputField.placeholderString = "https://docs.google.com/document/d/..."
        alert.accessoryView = inputField

        alert.addButton(withTitle: "Promote")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        guard let docID = DraftSupport.extractGoogleDocID(from: inputField.stringValue) else {
            let message = "Paste a valid Google Docs URL or document ID."
            statusMessage = message
            activeAlert = AppAlert(title: "Invalid Google draft link", message: message)
            return
        }

        do {
            let pointerURL = DraftSupport.preferredGoogleDraftPointerURL(for: item)
            try DraftSupport.googleDraftPointerContents(docID: docID)
                .write(to: pointerURL, atomically: true, encoding: .utf8)
            reloadWorkspace()

            if let itemID = workspaceItemID(forPath: item.path) {
                select(.workspace(itemID))
            }

            statusMessage = "Promoted Google draft"
        } catch {
            statusMessage = error.localizedDescription
            activeAlert = AppAlert(title: "Could not promote Google draft", message: error.localizedDescription)
        }
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
                assignedProjectPath: nil,
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
            assignedProjectPath: nil,
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
                assignedProjectPath: current.assignedProjectPath,
                assignedAt: current.assignedAt,
                assignedDestinationPath: current.assignedDestinationPath
            )
        }
    }

    func assignCaptureRecord(_ recordID: String, to project: WorkspaceItem, note: String) async {
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
                assignedProjectPath: existing.assignedProjectPath,
                assignedAt: existing.assignedAt,
                assignedDestinationPath: existing.assignedDestinationPath
            )
        }

        do {
            let destinationURL = try await copyCaptureRecord(
                from: URL(fileURLWithPath: importedStoragePath),
                into: project.url.appendingPathComponent("docs", isDirectory: true)
            )

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
                    assignedProjectPath: project.path,
                    assignedAt: .now,
                    assignedDestinationPath: destinationURL.path
                )
            }

            reloadWorkspace()
            statusMessage = "Assigned \(current.displayTitle) to \(project.title)"
        } catch {
            updateCaptureRecord(recordID) { existing in
                CaptureRecord(
                    id: existing.id,
                    displayName: existing.displayName,
                    originalSourcePath: existing.originalSourcePath,
                    importedStoragePath: existing.importedStoragePath,
                    capturedAt: existing.capturedAt,
                    captureType: existing.captureType,
                    state: .failed,
                    failureDescription: error.localizedDescription,
                    userNote: normalizedNote.isEmpty ? nil : normalizedNote,
                    assignedProjectPath: existing.assignedProjectPath,
                    assignedAt: existing.assignedAt,
                    assignedDestinationPath: existing.assignedDestinationPath
                )
            }
            statusMessage = "Could not assign \(current.displayTitle)"
        }
    }

    private func reloadWorkspaceQueryState() {
        let liveSnapshot = scanner.scan()
        snapshot = liveSnapshot
        catalog.replace(with: liveSnapshot)
        workspaceQueries = WorkspaceQueryStore(snapshot: catalog.loadSnapshot() ?? liveSnapshot)
    }

    private func reloadCaptureState() {
        if let storedRecords = captureStore.loadRecords() {
            captureRecords = storedRecords.sorted { $0.capturedAt > $1.capturedAt }
            return
        }

        captureRecords = []
        captureStore.replace(with: captureRecords)
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
        journalismWorkflowHubSupportDirectory()
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

        if workflow.id == "scaffold-project", run.exitCode == 0, let scaffoldContext {
            completeScaffoldProject(using: scaffoldContext)
            statusMessage = scaffoldContext.sourceMaterialChoice == .now
                ? "Project created. Add documents now."
                : "Created project"
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

    private func completeScaffoldProject(using context: ScaffoldCompletionContext) {
        presentScaffoldPostCreate(
            mode: .created,
            projectTitle: context.projectTitle,
            projectRoot: context.projectRoot,
            readmePath: context.readmePath,
            sourceMaterialChoice: context.sourceMaterialChoice
        )
    }

    private func presentScaffoldPostCreate(
        mode: ScaffoldPostCreateMode,
        projectTitle: String,
        projectRoot: String,
        readmePath: String,
        sourceMaterialChoice: ScaffoldSourceMaterialChoice
    ) {
        let postCreateState = ScaffoldPostCreateState(
            id: projectRoot,
            mode: mode,
            projectTitle: projectTitle,
            projectRoot: projectRoot,
            readmePath: readmePath,
            sourceMaterialChoice: sourceMaterialChoice,
            shouldAutoPromptForDocuments: sourceMaterialChoice == .now,
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
            sourceMaterialChoice: sourceMaterialChoice
        )
    }

    private func workspaceItemID(forPath path: String) -> String? {
        workspaceQueries.items.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
                == URL(fileURLWithPath: path).standardizedFileURL.path
        })?.id
    }

    private func resolveDraftTemplateURL() throws -> URL {
        if let savedTemplateURL = DraftTemplatePreferences.savedURL() {
            return savedTemplateURL
        }

        let suggestedTemplateURL = DraftSupport.suggestedTemplateURL()
        let legacySavedTemplateURL = DraftTemplatePreferences.legacySavedURL()

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let docxType = UTType(filenameExtension: "docx") {
            panel.allowedContentTypes = [docxType]
        }
        panel.prompt = "Use template"
        panel.message = draftTemplateSelectionMessage(
            suggestedTemplateURL: suggestedTemplateURL,
            legacySavedTemplateURL: legacySavedTemplateURL
        )
        panel.directoryURL = legacySavedTemplateURL?.deletingLastPathComponent()
            ?? suggestedTemplateURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)

        guard panel.runModal() == .OK, let templateURL = panel.url else {
            throw NSError(
                domain: "JournalismWorkflowHub.DraftTemplate",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Draft creation was cancelled because no `.docx` template was selected."]
            )
        }

        DraftTemplatePreferences.persist(templateURL)
        return templateURL
    }

    private func draftTemplateSelectionMessage(
        suggestedTemplateURL: URL?,
        legacySavedTemplateURL: URL?
    ) -> String {
        if let legacySavedTemplateURL {
            return "Choose the `.docx` draft template the scaffold should copy into new projects. Re-select `\(legacySavedTemplateURL.lastPathComponent)` once so the app keeps permission to read it."
        }

        if let suggestedTemplateURL {
            return "Choose the `.docx` draft template the scaffold should copy into new projects. Suggested: `\(suggestedTemplateURL.lastPathComponent)` in `\(suggestedTemplateURL.deletingLastPathComponent().path)`."
        }

        return "Choose the `.docx` draft template the scaffold should copy into new projects."
    }

    private func createLocalDraft(from templateURL: URL, in projectURL: URL, projectTitle: String) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = projectURL.appendingPathComponent(DraftSupport.localDraftFilename(projectTitle: projectTitle))

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw NSError(
                domain: "JournalismWorkflowHub.DraftTemplate",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "A draft already exists at \(destinationURL.path)."]
            )
        }

        try SecurityScopedAccess.withAccess(to: [templateURL, projectURL]) {
            try fileManager.copyItem(at: templateURL, to: destinationURL)
        }
        return destinationURL
    }

    private func importDocuments(from urls: [URL], into docsURL: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
        var importedPaths: [String] = []

        for url in urls {
            let destination = uniqueImportDestination(for: url, in: docsURL)
            try SecurityScopedAccess.withAccess(to: [url, docsURL]) {
                try FileManager.default.copyItem(at: url, to: destination)
            }
            importedPaths.append(destination.path)
        }

        return importedPaths
    }

    private func uniqueImportDestination(for sourceURL: URL, in docsURL: URL) -> URL {
        let fileManager = FileManager.default
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

    private func appendCaptureRecords(_ records: [CaptureRecord]) {
        captureRecords.append(contentsOf: records)
        captureRecords.sort { $0.capturedAt > $1.capturedAt }
        captureStore.replace(with: captureRecords)
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
            assignedProjectPath: current.assignedProjectPath,
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

    private func summarizeScaffoldDocsOverview(for state: ScaffoldPostCreateState) async throws {
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
        let importedPaths = state.importedPaths.sorted()
        let projectRoot = state.projectRoot

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = pythonExecutable
            process.arguments = [scriptPath, "--project-root", projectRoot]
                + importedPaths.flatMap { ["--imported-path", $0] }
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
            let destinationURL = uniqueImportDestinationForCapture(sourceURL: normalizedSource, in: normalizedDocs, fileManager: fileManager)
            try SecurityScopedAccess.withAccess(to: [normalizedSource, normalizedDocs]) {
                try fileManager.copyItem(at: normalizedSource, to: destinationURL)
            }
            return destinationURL
        }.value
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

private func uniqueImportDestinationForCapture(sourceURL: URL, in docsURL: URL, fileManager: FileManager) -> URL {
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
}

struct AppAlert: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
}
