import Foundation
import AppKit
import SwiftUI

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
    @Published var hasCompletedOnboarding: Bool
    @Published var scaffoldProjectWizardDraft = ScaffoldProjectWizardDraft()
    @Published var scaffoldProjectWizardStep: ScaffoldProjectWizardStep = .workingTitle
    @Published var scaffoldPostCreateState: ScaffoldPostCreateState?
    @Published private(set) var hiddenWorkflowCount: Int = 0
    @Published private(set) var workflowPreflightReports: [String: WorkflowPreflightReport] = [:]
    @Published private(set) var canNavigateBack: Bool = false
    @Published private(set) var canNavigateForward: Bool = false

    private var scanner: WorkspaceScanner
    private var catalog: any WorkspaceCataloging
    private var workspaceQueries: WorkspaceQueryStore = .empty
    private var runner: CommandRunner
    private var backHistory: [SidebarSelection] = []
    private var forwardHistory: [SidebarSelection] = []

    init(
        configuration: AppConfiguration = AppDefaults.configuration,
        catalog: (any WorkspaceCataloging)? = nil
    ) {
        self.appProfile = configuration.profile
        self.workspaceRoot = configuration.workspaceRoot
        self.demoWorkspaceRoot = configuration.demoWorkspaceRoot
        self.hasCompletedOnboarding = OnboardingPreferences.hasCompleted()
        self.scanner = WorkspaceScanner(workspaceRoot: configuration.workspaceRoot)
        self.catalog = catalog ?? WorkspaceCatalogStore(workspaceRoot: configuration.workspaceRoot)
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

    private func reloadWorkspaceQueryState() {
        let liveSnapshot = scanner.scan()
        snapshot = liveSnapshot
        catalog.replace(with: liveSnapshot)
        workspaceQueries = WorkspaceQueryStore(snapshot: catalog.loadSnapshot() ?? liveSnapshot)
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

    private func importDocuments(from urls: [URL], into docsURL: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true, attributes: nil)
        var importedPaths: [String] = []

        for url in urls {
            let destination = uniqueImportDestination(for: url, in: docsURL)
            try FileManager.default.copyItem(at: url, to: destination)
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
