import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List(selection: bindingForSelection) {
            Section {
                Button {
                    store.select(.overview)
                } label: {
                    Label("Workspace overview", systemImage: "house")
                }
                .buttonStyle(.plain)

                if store.appProfile.showsPlanCenter {
                    Button {
                        store.select(.planCenter)
                    } label: {
                        Label("Plan center", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    store.select(.publication)
                } label: {
                    Label("Publication index", systemImage: "newspaper")
                }
                .buttonStyle(.plain)
            }

            Section("Workspace") {
                ForEach(WorkspaceSection.allCases, id: \.self) { section in
                    let items = store.filteredWorkspaceItems.filter { $0.section == section }
                    if !items.isEmpty {
                        DisclosureGroup(section.label) {
                            ForEach(items) { item in
                                Button {
                                    store.select(.workspace(item.id))
                                } label: {
                                    WorkspaceRow(item: item)
                                }
                                .buttonStyle(.plain)
                                .tag(SidebarSelection.workspace(item.id))
                            }
                        }
                    }
                }
            }

            Section("Workflows") {
                ForEach(store.filteredWorkflows) { workflow in
                    Button {
                        store.select(.workflow(workflow.id))
                    } label: {
                        WorkflowRow(
                            workflow: workflow,
                            report: store.workflowPreflightReport(for: workflow)
                        )
                    }
                    .buttonStyle(.plain)
                    .tag(SidebarSelection.workflow(workflow.id))
                }
            }

            Section("Runs") {
                ForEach(store.runs) { run in
                    Button {
                        store.select(.run(run.id))
                    } label: {
                        RunRow(run: run, isSelected: selectionMatchesRun(run.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $store.searchText, prompt: "Search projects, workflows, runs")
        .listStyle(.sidebar)
        .navigationTitle("Journalism Hub")
    }

    private var bindingForSelection: Binding<SidebarSelection?> {
        Binding(
            get: { Optional(store.selection) },
            set: { newValue in
                if let newValue {
                    store.select(newValue)
                }
            }
        )
    }

    private func selectionMatchesRun(_ id: String) -> Bool {
        if case .run(let selected) = store.selection {
            return selected == id
        }
        return false
    }
}

struct DetailView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding(24)
        }
        .sheet(item: $store.scaffoldPostCreateState) { state in
            ScaffoldPostCreateSheet(state: state)
                .environmentObject(store)
        }
        .alert(item: $store.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(AppPalette.title)
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppPalette.subtle)
                    .textSelection(.enabled)
            }
            Spacer()
            HStack(spacing: 12) {
                primaryActionMenu
                statusChip
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.selection {
        case .overview:
            OverviewView()
        case .planCenter:
            PlanningCenterView()
        case .publication:
            PublicationView()
        case .workspace(let id):
            if let item = store.workspaceItem(for: id) {
                WorkspaceDetailView(item: item)
            } else {
                EmptyStateView(title: "Missing folder", message: "The selected folder could not be found.")
            }
        case .workflow(let id):
            if let workflow = store.workflows.first(where: { $0.id == id }) {
                WorkflowDetailView(workflow: workflow)
            } else {
                EmptyStateView(title: "Missing workflow", message: "The selected workflow could not be found.")
            }
        case .run(let id):
            if let run = store.runs.first(where: { $0.id == id }) {
                RunDetailView(run: run)
            } else {
                EmptyStateView(title: "Missing run", message: "The selected run could not be found.")
            }
        }
    }

    private var title: String {
        switch store.selection {
        case .overview:
            return "Overview"
        case .planCenter:
            return "Plan center"
        case .publication:
            return "Publication index"
        case .workspace(let id):
            return store.workspaceItem(for: id)?.title ?? "Workspace item"
        case .workflow(let id):
            return store.workflows.first(where: { $0.id == id })?.label ?? "Workflow"
        case .run(let id):
            return store.runs.first(where: { $0.id == id })?.workflowLabel ?? "Run"
        }
    }

    private var subtitle: String {
        switch store.selection {
        case .overview:
            return store.isStandaloneMode
                ? "Standalone audit view over a demo or external workspace."
                : "Current reporting work, next actions, and operational follow-up."
        case .planCenter:
            return "Roadmap, backlog, architecture notes, and automation ideas."
        case .publication:
            return "PDF-first archive mapping and missing-project review."
        case .workspace(let id):
            return store.workspaceItem(for: id)?.path ?? ""
        case .workflow(let id):
            return store.workflows.first(where: { $0.id == id })?.description ?? ""
        case .run(let id):
            return store.runs.first(where: { $0.id == id })?.commandPreview ?? ""
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        let text = store.statusMessage
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppPalette.card.opacity(0.85), in: Capsule())
            .foregroundStyle(AppPalette.subtle)
    }

    @ViewBuilder
    private var primaryActionMenu: some View {
        if store.isStandaloneMode {
            Menu {
                Button("Open workspace root") {
                    store.select(.workflow("open-workspace-root"))
                }

                Button("Inspect sample project") {
                    if let firstItem = store.firstWorkspaceItem {
                        store.select(.workspace(firstItem.id))
                    }
                }
                .disabled(store.firstWorkspaceItem == nil)
            } label: {
                HeaderActionMenuLabel(
                    title: "Audit actions",
                    systemImage: "plus",
                    prominence: .secondary
                )
            }
        } else {
            Menu {
                Button("New project") {
                    store.select(.workflow("scaffold-project"))
                }

                Button("Brainstorm from archive") {
                    store.select(.workflow("article-brain-brief"))
                }
                .disabled(!store.workflows.contains(where: { $0.id == "article-brain-brief" }))
            } label: {
                HeaderActionMenuLabel(
                    title: "New work",
                    systemImage: "plus",
                    prominence: .primary
                )
            }
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var expandedProjectIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            overviewHeader
            if store.isStandaloneMode {
                standaloneAuditSection
            }
            overviewPrimaryBand
            lowerSections
        }
        .frame(maxWidth: 900, alignment: .leading)
    }

    private var overviewHeader: some View {
        Text("Active reporting projects first, then the next actions and follow-up work that should not surprise you later.")
            .font(.body)
            .foregroundStyle(AppPalette.subtle)
    }

    private var standaloneAuditSection: some View {
        SectionCard(title: "Standalone mode") {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    store.isUsingDemoWorkspace
                        ? "This run is using the bundled demo workspace so you can audit the shell without relying on the full newsroom environment."
                        : "This run is in standalone mode. Portable workflows stay visible; local newsroom workflows are hidden until the standalone audit is complete."
                )
                .foregroundStyle(AppPalette.subtle)

                if store.hiddenWorkflowCount > 0 {
                    Text("\(store.hiddenWorkflowCount) local-only workflows are hidden in this profile.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.title)
                }
            }
        }
    }

    private var refreshWorkspaceButton: some View {
        Button {
            store.reloadAll()
        } label: {
            Label("Refresh workspace", systemImage: "arrow.clockwise")
        }
        .help("Rescan the workspace, reload plan docs, refresh workflows, and reload saved runs.")
    }

    @ViewBuilder
    private var overviewPrimaryBand: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                overviewWorkbenchSection
                    .frame(minWidth: 250, idealWidth: 272, maxWidth: 292, alignment: .topLeading)

                activeProjectsSection
                    .frame(minWidth: 0, idealWidth: 530, maxWidth: 560, alignment: .topLeading)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 18) {
                overviewWorkbenchSection
                activeProjectsSection
            }
        }
    }

    private var overviewWorkbenchSection: some View {
        SectionCard(title: store.isStandaloneMode ? "Audit actions" : "New work") {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    store.isStandaloneMode
                        ? "Keep the audit obvious: open the sample root or jump into the first project without digging through the sidebar."
                        : "Keep intake obvious: starting a project should read as the clearest action on the home screen."
                )
                .font(.subheadline)
                .foregroundStyle(AppPalette.subtle)

                Menu {
                    if store.isStandaloneMode {
                        Button("Open workspace root") {
                            store.select(.workflow("open-workspace-root"))
                        }

                        Button("Inspect sample project") {
                            if let firstItem = store.firstWorkspaceItem {
                                store.select(.workspace(firstItem.id))
                            }
                        }
                        .disabled(store.firstWorkspaceItem == nil)
                    } else {
                        Button("New project") {
                            store.select(.workflow("scaffold-project"))
                        }

                        Button("Brainstorm from archive") {
                            store.select(.workflow("article-brain-brief"))
                        }
                        .disabled(!store.workflows.contains(where: { $0.id == "article-brain-brief" }))
                    }
                } label: {
                    OverviewPrimaryMenuLabel(
                        title: store.isStandaloneMode ? "Open audit actions" : "Start new work",
                        detail: store.isStandaloneMode
                            ? "Inspect the sample workspace from a single clear entry point."
                            : "Create a fresh project with the guided scaffold or start from archive research.",
                        systemImage: store.isStandaloneMode ? "compass.drawing" : "plus.circle.fill"
                    )
                }

                refreshWorkspaceButton
                    .controlSize(.small)
            }
        }
    }

    private var activeProjectsSection: some View {
        SectionCard(title: "Active Projects") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep the live reporting desk in view first: a few active projects, compact and expandable.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.subtle)

                if store.overviewProjectSummaries.isEmpty {
                    EmptyStateView(
                        title: "No active reporting projects",
                        message: "Add or activate a journalism project to make the home screen feel like a real editorial desk."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(store.overviewProjectSummaries.enumerated()), id: \.element.id) { index, summary in
                            OverviewProjectRow(
                                summary: summary,
                                isExpanded: expandedProjectIDs.contains(summary.id),
                                toggleExpanded: { toggleExpanded(for: summary.id) },
                                primaryAction: { store.openOverviewTarget(summary.primaryTarget) }
                            )

                            if index < store.overviewProjectSummaries.count - 1 {
                                Divider()
                                    .padding(.leading, 2)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var lowerSections: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                suggestedActionsSection
                    .frame(minWidth: 236, idealWidth: 266, maxWidth: 292, alignment: .topLeading)
                operationsSection
                    .frame(minWidth: 236, idealWidth: 266, maxWidth: 292, alignment: .topLeading)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 18) {
                suggestedActionsSection
                operationsSection
            }
        }
    }

    private var suggestedActionsSection: some View {
        SectionCard(title: "Editorial next actions") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Project-facing follow-up that should change reporting work now, not background maintenance.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.subtle)

                ForEach(store.overviewActions) { action in
                    SuggestedActionRow(
                        title: action.title,
                        summary: action.body,
                        buttonTitle: action.buttonTitle,
                        count: action.count,
                        action: { store.openOverviewTarget(action.target) }
                    )
                }
            }
        }
    }

    private var operationsSection: some View {
        SectionCard(title: "Operations follow-up") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Workflow failures, publication hygiene, and metadata cleanup stay visible here without pretending to be editorial next steps.")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.subtle)

                ForEach(store.overviewOperations) { operation in
                    OverviewOperationRow(
                        operation: operation,
                        action: { store.openOverviewTarget(operation.target) }
                    )
                }
            }
        }
    }

    private func toggleExpanded(for id: String) {
        if expandedProjectIDs.contains(id) {
            expandedProjectIDs.remove(id)
        } else {
            expandedProjectIDs.insert(id)
        }
    }
}

struct WorkspaceDetailView: View {
    @EnvironmentObject private var store: AppStore
    let item: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "Key links") {
                VStack(alignment: .leading, spacing: 12) {
                    if let draft = item.canonicalDraftDocument {
                        Text(item.draftTargetExplanation(for: draft))
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.subtle)

                        HStack {
                            Button("Open draft") {
                                store.openPreferredDraft(for: item)
                            }
                            Button("Open folder") {
                                store.openFolder(for: item)
                            }
                            if draft.cachePath != nil {
                                Button("Open local cache") {
                                    store.openDocumentCache(draft)
                                }
                            }
                            if let googleDriveURL = item.googleDriveURL {
                                Button("Open Drive folder") {
                                    store.openURL(googleDriveURL)
                                }
                            }
                        }
                    } else {
                        Text("No canonical draft target is clear yet. The project folder is still available below.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.subtle)

                        HStack {
                            Button("Open folder") {
                                store.openFolder(for: item)
                            }
                            if let googleDriveURL = item.googleDriveURL {
                                Button("Open Drive folder") {
                                    store.openURL(googleDriveURL)
                                }
                            }
                        }
                    }
                }
            }

            SectionCard(title: "Project at a glance") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use this section to understand what kind of project this is, how it should be handled, and how much working material sits at the root.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.subtle)

                    MetadataGrid(rows: [
                        ("Section", item.section.label),
                        ("Project kind", item.projectType.label),
                        ("Current stage", item.lifecycleStage),
                        ("Handling", item.safetyPosture.label),
                        ("Workspace path", item.path),
                        ("Root documents", "\(item.documents.count)"),
                        ("Direct files", "\(item.directFileCount)"),
                        ("Direct folders", "\(item.directFolderCount)"),
                        ("Markdown", "\(item.markdownFiles)"),
                        ("PDFs", "\(item.pdfFiles)"),
                        ("Google Doc pointers", "\(item.gdocFiles)")
                    ])
                }
            }

            SectionCard(title: "How to work with this project") {
                VStack(alignment: .leading, spacing: 14) {
                    if !item.subtitle.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current summary")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.title)
                            Text(item.subtitle)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("This project still needs a clearer working summary in its README.")
                            .font(.body)
                            .foregroundStyle(AppPalette.subtle)
                    }

                    if !item.agentsSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Local rules")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.title)
                            Text(item.agentsSummary)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("No local rules are captured in `AGENTS.md` yet.")
                            .font(.caption)
                            .foregroundStyle(AppPalette.subtle)
                    }

                    HStack {
                        Button("Open README") { store.openReadme(for: item) }
                        if let agentsURL = item.agentsURL {
                            Button("Open local rules") {
                                store.openURL(agentsURL)
                            }
                        }
                    }
                }
            }

            if !item.frontmatter.isEmpty {
                SectionCard(title: "Structured metadata") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trusted fields from the root README that drive classification and workflow behavior.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.subtle)
                        ForEach(item.frontmatter.keys.sorted(), id: \.self) { key in
                            KeyValueRow(key: key, value: item.frontmatter[key] ?? "")
                        }
                    }
                }
            }

            if !item.documents.isEmpty {
                SectionCard(title: "Detected documents") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("These are the root-level drafts, notes, pointers, and local copies the scanner found. Snapshot copies stay visible here, but they do not automatically become the main draft link.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.subtle)

                        ForEach(item.documents) { document in
                            WorkspaceDocumentRow(
                                document: document,
                                isPreferredDraft: item.canonicalDraftDocument == document,
                                isLikelySnapshot: item.isLikelyDerivedSnapshot(document),
                                openDocument: { store.openDocument(document) },
                                openCache: { store.openDocumentCache(document) }
                            )
                        }
                    }
                }
            }

            SectionCard(title: "Project maintenance") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These actions update derived project state or prepare local Google Doc cache placeholders. They do not change which draft link the app treats as canonical.")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.subtle)

                    HStack {
                        Button("Open folder") { store.openFolder(for: item) }
                        if item.hasGoogleDocPointers {
                            Button("Prepare Google Doc cache") {
                                store.select(.workspace(item.id))
                                store.select(.workflow("refresh-project-google-doc-prep"))
                                store.runSelectedWorkflow()
                            }
                        }
                        if item.isProjectRoot {
                            Button("Refresh README") {
                                store.select(.workspace(item.id))
                                store.select(.workflow("build-project-readme"))
                                store.runSelectedWorkflow()
                            }
                        }
                    }
                }
            }

            if let matches = publicationMatches {
                SectionCard(title: "Publication links") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(matches, id: \.id) { story in
                            PublicationStoryRow(story: story)
                        }
                    }
                }
            }
        }
        .task {
            store.reloadWorkflows()
        }
    }

    private var publicationMatches: [PublicationStory]? {
        let allMatches = store.snapshot.publication.storiesByYear.values.flatMap { $0 }
        let selected = allMatches.filter { $0.projectPath == item.path }
        return selected.isEmpty ? nil : selected.sorted { $0.pdfTitle < $1.pdfTitle }
    }
}

struct WorkflowDetailView: View {
    @EnvironmentObject private var store: AppStore
    let workflow: WorkflowDefinition

    var body: some View {
        if workflow.id == "scaffold-project" {
            ScaffoldProjectWizardView(workflow: workflow)
                .onAppear {
                    store.ensureSelectedWorkflowDefaults()
                }
        } else {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "Workflow") {
                MetadataGrid(rows: [
                    ("Category", workflow.category),
                    ("Availability", workflow.availability.label),
                    ("Selection", workflow.selectionRequirement.rawValue),
                    ("Writes", workflow.isWriteAction ? "Yes" : "No"),
                    ("Working dir", workflow.workingDirectoryTemplate)
                ])
                if !workflow.note.isEmpty {
                    Text(workflow.note)
                        .foregroundStyle(AppPalette.subtle)
                        .textSelection(.enabled)
                }
            }

            SectionCard(title: "Preflight") {
                let report = store.workflowPreflightReport(for: workflow)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        WorkflowStatusBadge(status: report.status)
                        Text(report.summary)
                            .foregroundStyle(AppPalette.subtle)
                            .textSelection(.enabled)
                    }

                    if !report.missingItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Missing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.title)
                            ForEach(report.missingItems, id: \.self) { item in
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.subtle)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let setupHint = report.setupHint, !setupHint.isEmpty {
                        Text(setupHint)
                            .font(.caption)
                            .foregroundStyle(AppPalette.subtle)
                            .textSelection(.enabled)
                    }
                }
            }

            if !workflow.parameters.isEmpty {
                SectionCard(title: "Parameters") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(workflow.parameters) { spec in
                            WorkflowParameterEditor(
                                spec: spec,
                                value: store.selectedInputs[workflow.id] ?? WorkflowParameterState(),
                                workflowID: workflow.id,
                                onTextChange: { store.setText($0, for: workflow.id, fieldID: spec.id) },
                                onBoolChange: { store.setBool($0, for: workflow.id, fieldID: spec.id) }
                            )
                        }
                    }
                }
            }

            SectionCard(title: "Command preview") {
                Text(previewText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "Artifacts") {
                if let selection = store.selectedWorkspaceItem, workflow.selectionRequirement != .none {
                    Text("Selected item: \(selection.path)")
                        .foregroundStyle(AppPalette.subtle)
                        .textSelection(.enabled)
                }
                if workflow.isWriteAction {
                    Text("This workflow writes to the workspace. Confirm the target path before running.")
                        .foregroundStyle(AppPalette.subtle)
                        .textSelection(.enabled)
                }
                if workflow.selectionRequirement != .none && store.selectedWorkspaceItem == nil {
                    Text("Select a workspace item in the sidebar first.")
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(title: "Actions") {
                HStack {
                    Button("Run workflow") {
                        store.runSelectedWorkflow()
                    }
                    .disabled(
                        store.selectedWorkflow?.id != workflow.id
                            || store.isRunning
                            || !store.workflowPreflightReport(for: workflow).isRunnable
                    )
                    Button("Open workspace root") {
                        store.openPath(store.workspaceRoot.path)
                    }
                }
            }
        }
        .onAppear {
            store.ensureSelectedWorkflowDefaults()
        }
        }
    }

    private var previewText: String {
        guard let state = store.selectedInputs[workflow.id] else { return workflow.commandPreview }
        do {
            let resolved = try WorkflowRegistry(workspaceRoot: store.workspaceRoot, appProfile: store.appProfile).resolveCommand(
                workflow: workflow,
                state: state,
                selection: store.selectedWorkspaceItem
            )
            return [
                "cd \(resolved.workingDirectory)",
                resolved.commandPreview
            ].joined(separator: "\n")
        } catch {
            return error.localizedDescription
        }
    }
}

struct RunDetailView: View {
    @EnvironmentObject private var store: AppStore
    let run: WorkflowRun

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "Run metadata") {
                MetadataGrid(rows: [
                    ("Workflow", run.workflowLabel),
                    ("Started", run.startedAt),
                    ("Finished", run.finishedAt),
                    ("Exit code", "\(run.exitCode)"),
                    ("Working dir", run.workingDirectory)
                ])
            }

            SectionCard(title: "Artifacts") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(run.artifactPaths, id: \.self) { path in
                        Button {
                            store.openPath(path)
                        } label: {
                            Label(path, systemImage: "doc")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SectionCard(title: "Output") {
                Text(store.selectedRunOutput.isEmpty ? store.loadRunText(run) : store.selectedRunOutput)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SectionCard(title: "Actions") {
                HStack {
                    Button("Refresh output") {
                        store.refreshSelectedRun()
                    }
                    Button("Open stdout") {
                        store.openPath(run.stdoutPath)
                    }
                    Button("Open stderr") {
                        store.openPath(run.stderrPath)
                    }
                }
            }
        }
    }
}

struct PublicationView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatGridView(
                stats: [
                    StatCard(title: "Matched PDFs", value: "\(store.snapshot.publication.matchedCount)", detail: "linked to project READMEs"),
                    StatCard(title: "Missing projects", value: "\(store.snapshot.publication.missingCount)", detail: "have no linked published PDF")
                ]
            )

            if !store.snapshot.publication.storiesByYear.isEmpty {
                SectionCard(title: "Published stories") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.snapshot.publication.storiesByYear.keys.sorted(), id: \.self) { year in
                            let stories = store.snapshot.publication.storiesByYear[year] ?? []
                            DisclosureGroup(year) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(stories) { story in
                                        PublicationStoryRow(story: story)
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
            }

            if !store.snapshot.publication.projectsByYear.isEmpty {
                SectionCard(title: "Projects without linked PDF") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.snapshot.publication.projectsByYear.keys.sorted(), id: \.self) { year in
                            let projects = store.snapshot.publication.projectsByYear[year] ?? []
                            DisclosureGroup(year) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(projects) { project in
                                        PublicationProjectRow(project: project)
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ScaffoldPostCreateSheet: View {
    @EnvironmentObject private var store: AppStore
    let state: ScaffoldPostCreateState
    @State private var didAutoPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(titleText)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(AppPalette.title)

            Text(summaryText)
                .foregroundStyle(AppPalette.subtle)

            MetadataGrid(rows: [
                ("Project", state.projectTitle),
                ("Folder", state.projectRoot),
                ("Docs folder", state.docsURL.path),
                ("Imported", state.importedItemCount == 0 ? "Nothing added yet" : "\(state.importedItemCount) item(s)")
            ])

            HStack {
                Button(primaryButtonTitle) {
                    store.addDocumentsToScaffoldProject()
                }
                .buttonStyle(.borderedProminent)

                Button("Show in app") {
                    store.openScaffoldPostCreateProject()
                }

                Button("Open README") {
                    store.openScaffoldPostCreateReadme()
                }

                if state.importedItemCount > 0 {
                    Button("Open docs folder") {
                        store.openScaffoldPostCreateDocsFolder()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    store.dismissScaffoldPostCreate()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620)
        .onAppear {
            guard state.shouldAutoPromptForDocuments,
                  state.sourceMaterialChoice == .now,
                  state.importedItemCount == 0,
                  !didAutoPrompt else {
                return
            }
            didAutoPrompt = true
            store.addDocumentsToScaffoldProject()
        }
    }

    private var primaryButtonTitle: String {
        if state.sourceMaterialChoice == .now {
            return state.importedItemCount == 0 ? "Add documents now" : "Add more documents"
        }
        return "Add documents"
    }

    private var titleText: String {
        switch state.mode {
        case .created:
            return "Project created"
        case .reused:
            return "Existing project selected"
        }
    }

    private var summaryText: String {
        if state.sourceMaterialChoice == .now {
            switch state.mode {
            case .created:
                return state.importedItemCount == 0
                    ? "The project is ready. Add source material now and the app will copy it into this project's docs folder."
                    : "The project is ready and source material has started landing in docs. You can add more, show it in the app, or jump into the README."
            case .reused:
                return state.importedItemCount == 0
                    ? "The existing project is ready. Add source material now and the app will copy it into this project's docs folder."
                    : "The existing project is active and source material has started landing in docs. You can add more, show it in the app, or jump into the README."
            }
        }

        switch state.mode {
        case .created:
            return "The project is ready. You can show it in the app now, inspect the README, or add source material whenever you are ready."
        case .reused:
            return "The existing project is ready. You can show it in the app now, inspect the README, or add source material whenever you are ready."
        }
    }
}

struct PlanningCenterView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.planningSnapshot.docs.isEmpty {
            EmptyStateView(
                title: "Plan center unavailable",
                message: "This profile does not include the private planning workspace, or the planning project could not be found at the expected location."
            )
        } else {
        VStack(alignment: .leading, spacing: 18) {
            StatGridView(
                stats: [
                    StatCard(title: "Plan docs", value: "\(store.planningSnapshot.docs.count)", detail: "roadmap, backlog, decisions, automation"),
                    StatCard(title: "Project", value: store.planningSnapshot.projectTitle, detail: "living planning workspace"),
                    StatCard(title: "Location", value: shortPath(store.planningSnapshot.projectPath), detail: "separate from execution code")
                ]
            )

            SectionCard(title: "Plan workspace") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The planning layer lives alongside the app code, not inside a story project.")
                        .foregroundStyle(AppPalette.subtle)
                    HStack {
                        Button("Open folder") {
                            store.openPath(store.planningSnapshot.projectPath)
                        }
                        Button("Open README") {
                            let url = URL(fileURLWithPath: store.planningSnapshot.projectPath)
                                .appendingPathComponent("README.md")
                            store.openURL(url)
                        }
                        Button("Refresh plan docs") {
                            store.reloadPlanning()
                        }
                    }
                }
            }

            ForEach(store.planningSnapshot.docs) { doc in
                SectionCard(title: doc.title) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !doc.summary.isEmpty {
                            Text(doc.summary)
                                .foregroundStyle(AppPalette.subtle)
                                .textSelection(.enabled)
                        }
                        markdownBody(displayBody(for: doc.body))
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Button("Open doc") {
                                store.openURL(doc.url)
                            }
                            Button("Open folder") {
                                store.openPath(URL(fileURLWithPath: doc.path).deletingLastPathComponent().path)
                            }
                        }
                    }
                }
            }
        }
        }
    }

    private func shortPath(_ path: String) -> String {
        guard path.count > 88 else { return path }
        return "…" + path.suffix(85)
    }

    private func markdownBody(_ body: String) -> Text {
        if let attributed = try? AttributedString(markdown: body) {
            return Text(attributed)
        }
        return Text(body)
    }

    private func displayBody(for body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ")
        }) else {
            return body
        }
        let remainder = lines.dropFirst(headingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? body : remainder
    }
}

struct WorkflowParameterEditor: View {
    let spec: WorkflowParameterSpec
    let value: WorkflowParameterState
    let workflowID: String
    let onTextChange: (String) -> Void
    let onBoolChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch spec.kind {
            case .boolean:
                Toggle(spec.label, isOn: Binding(get: {
                    value.boolValue(for: spec.id)
                }, set: { onBoolChange($0) }))
                .toggleStyle(.switch)
            case .choice:
                Text(spec.label)
                    .font(.headline)
                Picker("", selection: Binding(get: {
                    value.stringValue(for: spec.id).isEmpty ? (spec.choices?.first ?? "") : value.stringValue(for: spec.id)
                }, set: { onTextChange($0) })) {
                    ForEach(spec.choices ?? [], id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .pickerStyle(.menu)
            case .multiline:
                Text(spec.label)
                    .font(.headline)
                TextEditor(text: Binding(get: {
                    value.stringValue(for: spec.id)
                }, set: { onTextChange($0) }))
                .frame(minHeight: 90)
                .font(.system(.body, design: .monospaced))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppPalette.border))
            default:
                Text(spec.label)
                    .font(.headline)
                TextField("", text: Binding(get: {
                    value.stringValue(for: spec.id)
                }, set: { onTextChange($0) }))
                .textFieldStyle(.roundedBorder)
            }

            if let helpText = spec.helpText {
                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(AppPalette.subtle)
            }
        }
    }
}

struct WorkspaceRow: View {
    let item: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                WorkspaceBadge(text: item.projectType.label)
            }
            if !item.workspaceSummary.isEmpty {
                Text(item.workspaceSummary)
                    .font(.caption)
                    .foregroundStyle(AppPalette.subtle)
                    .lineLimit(2)
            }
            Text(item.safetyPosture.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppPalette.title)
        }
    }
}

struct WorkflowRow: View {
    let workflow: WorkflowDefinition
    let report: WorkflowPreflightReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(workflow.label)
                Spacer(minLength: 8)
                WorkflowAvailabilityBadge(availability: workflow.availability)
                WorkflowStatusBadge(status: report.status)
            }
            Text("\(workflow.category) • \(report.status.label)")
                .font(.caption)
                .foregroundStyle(AppPalette.subtle)
        }
    }
}

struct RunRow: View {
    let run: WorkflowRun
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.workflowLabel)
            Text("\(run.startedAt) • exit \(run.exitCode)")
                .font(.caption)
                .foregroundStyle(isSelected ? AppPalette.title : AppPalette.subtle)
        }
    }
}

struct WorkflowAvailabilityBadge: View {
    let availability: WorkflowAvailability

    var body: some View {
        Text(availability.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch availability {
        case .portable:
            return Color.green.opacity(0.14)
        case .optionalLocal:
            return Color.orange.opacity(0.14)
        case .privateHidden:
            return Color.red.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch availability {
        case .portable:
            return .green
        case .optionalLocal:
            return .orange
        case .privateHidden:
            return .red
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppPalette.title)
            content
        }
        .padding(18)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppPalette.border))
    }
}

struct StatCard: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

struct StatGridView: View {
    let stats: [StatCard]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 6) {
                    Text(stat.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.subtle)
                        .textCase(.uppercase)
                    Text(stat.value)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppPalette.title)
                    Text(stat.detail)
                        .font(.caption)
                        .foregroundStyle(AppPalette.subtle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AppPalette.border))
            }
        }
    }
}

struct MetadataGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.subtle)
                    Text(row.1)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(key)
                .frame(width: 160, alignment: .leading)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.subtle)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct PublicationStoryRow: View {
    @EnvironmentObject private var store: AppStore
    let story: PublicationStory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(story.pdfTitle)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(story.year)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.subtle)
            }
            Text(story.projectTitle)
                .foregroundStyle(AppPalette.subtle)
                .textSelection(.enabled)
            HStack {
                Button("Open PDF") { store.openURL(story.pdfURL) }
                Button("Open folder") { store.openURL(story.projectURL) }
                Button("Open README") { store.openURL(story.projectReadmeURL) }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct PublicationProjectRow: View {
    @EnvironmentObject private var store: AppStore
    let project: PublicationProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.title)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(project.publishedStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.subtle)
            }
            Text(project.slug)
                .foregroundStyle(AppPalette.subtle)
                .textSelection(.enabled)
            HStack {
                Button("Open folder") { store.openURL(project.url) }
                Button("Open README") { store.openURL(project.readmeURL) }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct SuggestedActionRow: View {
    let title: String
    let summary: String
    let buttonTitle: String
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppPalette.card.opacity(0.95), in: Capsule())
                        .overlay(Capsule().stroke(AppPalette.border))
                        .foregroundStyle(AppPalette.subtle)
                }
                Text(summary)
                    .foregroundStyle(AppPalette.subtle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(buttonTitle, action: action)
        }
        .padding(.vertical, 6)
    }
}

struct OverviewProjectRow: View {
    @EnvironmentObject private var store: AppStore
    let summary: OverviewProjectSummary
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.item.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppPalette.title)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        if let primaryFlag = summary.displayPrimaryFlag {
                            WorkspaceBadge(text: primaryFlag)
                        }
                    }

                    Text(projectSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.subtle)
                        .textSelection(.enabled)
                        .lineLimit(isExpanded ? 3 : 2)
                }
                Spacer()

                HStack(spacing: 10) {
                    if !isExpanded {
                        Button(summary.primaryButtonTitle, action: primaryAction)
                            .controlSize(.small)
                    }
                    Button(action: toggleExpanded) {
                        Label(isExpanded ? "Less" : "More", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.subtle)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if !collapsedShortcuts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(collapsedShortcuts) { shortcut in
                            Button(action: shortcut.action) {
                                Label(shortcut.label, systemImage: shortcut.iconName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(AppPalette.card.opacity(0.98), in: Capsule())
                                    .overlay(Capsule().stroke(AppPalette.border))
                                    .foregroundStyle(AppPalette.title)
                            }
                            .buttonStyle(.plain)
                            .help(shortcut.helpText)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary.nextStep)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button(summary.primaryButtonTitle, action: primaryAction)
                            .controlSize(.small)
                        Button("Open folder") {
                            store.openFolder(for: summary.item)
                        }
                        .controlSize(.small)
                        Button("Open README") {
                            store.openReadme(for: summary.item)
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 12) {
                        if let draft = summary.item.canonicalDraftDocument, draft.cachePath != nil {
                            Button("Open local cache") {
                                store.openDocumentCache(draft)
                            }
                            .buttonStyle(.borderless)
                        }
                        if let googleDriveURL = summary.item.googleDriveURL {
                            Button("Open Drive folder") {
                                store.openURL(googleDriveURL)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, 12)
    }

    private var projectSummaryText: String {
        if !summary.item.summary.isEmpty {
            return summary.item.summary
        }
        if !summary.item.subtitle.isEmpty {
            return summary.item.subtitle
        }
        return "This active project needs a clearer working summary."
    }

    private var collapsedShortcuts: [OverviewProjectShortcut] {
        var shortcuts = summary.item.overviewShortcutDocuments.map { document in
            OverviewProjectShortcut(
                id: document.id,
                label: document.role == .draft ? "Draft" : document.role.label,
                iconName: document.overviewIconName,
                helpText: document.title,
                action: { store.openDocument(document) }
            )
        }

        shortcuts.append(
            OverviewProjectShortcut(
                id: "\(summary.id)-folder",
                label: "Folder",
                iconName: "folder",
                helpText: "Open local project folder",
                action: { store.openFolder(for: summary.item) }
            )
        )

        if let googleDriveURL = summary.item.googleDriveURL, shortcuts.count < 3 {
            shortcuts.append(
                OverviewProjectShortcut(
                    id: "\(summary.id)-drive",
                    label: "Drive",
                    iconName: "folder",
                    helpText: "Open Drive folder",
                    action: { store.openURL(googleDriveURL) }
                )
            )
        }

        return shortcuts
    }
}

struct OverviewProjectShortcut: Identifiable {
    let id: String
    let label: String
    let iconName: String
    let helpText: String
    let action: () -> Void
}

struct OverviewOperationRow: View {
    let operation: OverviewOperationSummary
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(operation.title)
                        .font(.body.weight(.semibold))
                    Text("\(operation.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.subtle)
                }
                Text(operation.detail)
                    .foregroundStyle(AppPalette.subtle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(operation.buttonTitle, action: action)
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(AppPalette.subtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorkspaceDocumentRow: View {
    let document: WorkspaceDocument
    let isPreferredDraft: Bool
    let isLikelySnapshot: Bool
    let openDocument: () -> Void
    let openCache: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppPalette.title)
                    .textSelection(.enabled)

                Text(documentDetailText)
                    .font(.caption)
                    .foregroundStyle(AppPalette.subtle)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if isPreferredDraft {
                        WorkspaceBadge(text: "Preferred draft")
                    }
                    if isLikelySnapshot {
                        WorkspaceBadge(text: "Snapshot copy")
                    }
                    WorkspaceBadge(text: document.role.label)
                    WorkspaceBadge(text: document.provider.label)
                    DocumentCacheBadge(state: document.cacheState)
                    DocumentFreshnessBadge(freshness: document.freshness())
                }

                if let cachedOn = document.cachedOn, !cachedOn.isEmpty {
                    Text("Cached on \(cachedOn)")
                        .font(.caption)
                        .foregroundStyle(AppPalette.subtle)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(document.provider == .localFile ? "Open local file" : "Open in browser", action: openDocument)
                if document.cachePath != nil {
                    Button("Open local cache", action: openCache)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var documentDetailText: String {
        if isLikelySnapshot {
            return "Local snapshot kept for analysis or reference. It does not override the main draft target."
        }

        switch document.provider {
        case .localFile:
            return "\(document.role.label) stored locally and ready to open."
        case .googleDocPointer:
            return "Google Doc pointer with \(document.cacheState.label.lowercased()) local cache and \(document.freshness().label.lowercased()) freshness."
        }
    }
}

struct WorkspaceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppPalette.card.opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(AppPalette.border))
            .foregroundStyle(AppPalette.title)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HeaderActionMenuLabel: View {
    enum Prominence {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let prominence: Prominence

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch prominence {
        case .primary:
            return AppPalette.title
        case .secondary:
            return AppPalette.card
        }
    }

    private var foreground: Color {
        switch prominence {
        case .primary:
            return Color.white
        case .secondary:
            return AppPalette.title
        }
    }

    private var border: Color {
        switch prominence {
        case .primary:
            return AppPalette.title
        case .secondary:
            return AppPalette.border
        }
    }
}

private struct OverviewPrimaryMenuLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 12)

            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(10)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    AppPalette.title,
                    Color(red: 0.30, green: 0.43, blue: 0.39)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18))
        )
    }
}

struct DocumentCacheBadge: View {
    let state: WorkspaceDocumentCacheState

    var body: some View {
        Text(state.label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(backgroundColor.opacity(0.3)))
            .foregroundStyle(backgroundColor)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var backgroundColor: Color {
        switch state {
        case .localFile, .cachedText:
            return Color.green.opacity(0.9)
        case .cachedSummary, .titleStub:
            return Color.orange.opacity(0.9)
        case .notCached, .placeholder, .unknown:
            return Color.red.opacity(0.85)
        }
    }
}

struct DocumentFreshnessBadge: View {
    let freshness: WorkspaceDocumentFreshness

    var body: some View {
        Text(freshness.label)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(backgroundColor.opacity(0.3)))
            .foregroundStyle(backgroundColor)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var backgroundColor: Color {
        switch freshness {
        case .localFile, .fresh:
            return Color.green.opacity(0.9)
        case .aging, .undated:
            return Color.orange.opacity(0.9)
        case .needsFetch, .stale:
            return Color.red.opacity(0.85)
        }
    }
}

struct WorkflowStatusBadge: View {
    let status: WorkflowPreflightStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(backgroundColor.opacity(0.35)))
            .foregroundStyle(backgroundColor)
    }

    private var backgroundColor: Color {
        switch status {
        case .ready:
            return Color.green.opacity(0.9)
        case .needsSelection:
            return Color.orange.opacity(0.9)
        case .missingWorkingDirectory, .missingExecutable, .missingRequiredPath, .missingPythonModule, .invalidConfiguration:
            return Color.red.opacity(0.85)
        }
    }
}

enum AppPalette {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.97, blue: 0.94),
            Color(red: 0.94, green: 0.96, blue: 0.96)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let card = Color.white.opacity(0.78)
    static let border = Color(red: 0.80, green: 0.79, blue: 0.75).opacity(0.55)
    static let title = Color(red: 0.13, green: 0.19, blue: 0.16)
    static let subtle = Color(red: 0.35, green: 0.39, blue: 0.37)
}

private extension AppStore {
    func loadRunText(_ run: WorkflowRun) -> String {
        let stdout = (try? String(contentsOfFile: run.stdoutPath, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOfFile: run.stderrPath, encoding: .utf8)) ?? ""
        let text = [stdout.isEmpty ? nil : "STDOUT\n\(stdout)", stderr.isEmpty ? nil : "STDERR\n\(stderr)"]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        return text.isEmpty ? "No output captured." : text
    }
}
