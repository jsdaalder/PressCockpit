import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    let workspaceRoot: URL

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
    @Published var isRunning: Bool = false
    @Published var selectedRunOutput: String = ""

    private let scanner: WorkspaceScanner
    private let runner: CommandRunner

    init(workspaceRoot: URL = AppDefaults.workspaceRoot) {
        self.workspaceRoot = workspaceRoot
        self.scanner = WorkspaceScanner(workspaceRoot: workspaceRoot)
        self.runner = CommandRunner(workspaceRoot: workspaceRoot)
        reloadAll()
    }

    func reloadAll() {
        snapshot = scanner.scan()
        reloadPlanning()
        reloadWorkflows()
        reloadRuns()
    }

    func reloadWorkspace() {
        snapshot = scanner.scan()
    }

    func reloadPlanning() {
        planningSnapshot = PlanningStore(workspaceRoot: workspaceRoot).load()
    }

    func reloadWorkflows() {
        workflows = WorkflowRegistry(workspaceRoot: workspaceRoot).loadWorkflows(selection: selectedWorkspaceItem)
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
    }

    func reloadRuns() {
        runs = loadRuns()
    }

    var selectedWorkspaceItem: WorkspaceItem? {
        guard let selectedWorkspaceItemID else { return nil }
        return snapshot.items.first(where: { $0.id == selectedWorkspaceItemID })
    }

    var selectedWorkflow: WorkflowDefinition? {
        guard let selectedWorkflowID else { return nil }
        return workflows.first(where: { $0.id == selectedWorkflowID })
    }

    var filteredWorkspaceItems: [WorkspaceItem] {
        guard !searchText.isEmpty else { return snapshot.items }
        let query = searchText.lowercased()
        return snapshot.items.filter { item in
            item.title.lowercased().contains(query)
                || item.summary.lowercased().contains(query)
                || item.path.lowercased().contains(query)
                || item.tags.joined(separator: " ").lowercased().contains(query)
        }
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

    func select(_ selection: SidebarSelection) {
        self.selection = selection
        if case .workspace = selection {
            if case .workspace(let id) = selection {
                selectedWorkspaceItemID = id
            }
            reloadWorkflows()
        }
        if case .workflow = selection {
            if case .workflow(let id) = selection {
                selectedWorkflowID = id
            }
            ensureSelectedWorkflowDefaults()
        }
        if case .run(let id) = selection {
            selectedRunOutput = loadRunOutput(for: id)
        }
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
    }

    func setText(_ value: String, for workflowID: String, fieldID: String) {
        var state = selectedInputs[workflowID] ?? WorkflowParameterState()
        state.textValues[fieldID] = value
        selectedInputs[workflowID] = state
    }

    func setBool(_ value: Bool, for workflowID: String, fieldID: String) {
        var state = selectedInputs[workflowID] ?? WorkflowParameterState()
        state.booleanValues[fieldID] = value
        selectedInputs[workflowID] = state
    }

    func runSelectedWorkflow() {
        guard let workflow = selectedWorkflow else { return }
        let state = selectedInputs[workflow.id] ?? WorkflowParameterState()

        isRunning = true
        statusMessage = "Running \(workflow.label)…"

        Task {
            do {
                let run = try runner.run(workflow: workflow, state: state, selection: selectedWorkspaceItem)
                await MainActor.run {
                    self.runs.insert(run, at: 0)
                    self.selection = .run(run.id)
                    self.selectedRunOutput = self.loadRunOutput(for: run.id)
                    self.statusMessage = "Finished with exit code \(run.exitCode)"
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
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

    func openProjectRoot(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
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
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JournalismWorkflowHub", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
}

enum AppDefaults {
    static let workspaceRoot = URL(fileURLWithPath: "/Users/jandaalder/My Drive/coding_projects")
}
