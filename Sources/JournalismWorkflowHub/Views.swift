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

                Button {
                    store.select(.planCenter)
                } label: {
                    Label("Plan center", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.plain)

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
                        WorkflowRow(workflow: workflow)
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
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(AppPalette.title)
                Text(subtitle)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppPalette.subtle)
            }
            Spacer()
            statusChip
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
            if let item = store.snapshot.items.first(where: { $0.id == id }) {
                WorkspaceDetailView(item: item)
            } else {
                EmptyStateView(title: "Missing folder", body: "The selected folder could not be found.")
            }
        case .workflow(let id):
            if let workflow = store.workflows.first(where: { $0.id == id }) {
                WorkflowDetailView(workflow: workflow)
            } else {
                EmptyStateView(title: "Missing workflow", body: "The selected workflow could not be found.")
            }
        case .run(let id):
            if let run = store.runs.first(where: { $0.id == id }) {
                RunDetailView(run: run)
            } else {
                EmptyStateView(title: "Missing run", body: "The selected run could not be found.")
            }
        }
    }

    private var title: String {
        switch store.selection {
        case .overview:
            return "Workspace overview"
        case .planCenter:
            return "Plan center"
        case .publication:
            return "Publication index"
        case .workspace(let id):
            return store.snapshot.items.first(where: { $0.id == id })?.title ?? "Workspace item"
        case .workflow(let id):
            return store.workflows.first(where: { $0.id == id })?.label ?? "Workflow"
        case .run(let id):
            return store.runs.first(where: { $0.id == id })?.workflowLabel ?? "Run"
        }
    }

    private var subtitle: String {
        switch store.selection {
        case .overview:
            return "Project browser, publication coverage, and workflow launchpad."
        case .planCenter:
            return "Roadmap, backlog, architecture notes, and automation ideas."
        case .publication:
            return "PDF-first archive mapping and missing-project review."
        case .workspace(let id):
            return store.snapshot.items.first(where: { $0.id == id })?.path ?? ""
        case .workflow(let id):
            return store.workflows.first(where: { $0.id == id })?.description ?? ""
        case .run(let id):
            return store.runs.first(where: { $0.id == id })?.commandPreview ?? ""
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        let text = store.isRunning ? "Running" : store.statusMessage
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppPalette.card.opacity(0.85), in: Capsule())
            .foregroundStyle(AppPalette.subtle)
    }
}

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StatGridView(
                stats: [
                    StatCard(title: "Workspace items", value: "\(store.snapshot.items.count)", detail: "folders with README files"),
                    StatCard(title: "Published links", value: "\(store.snapshot.publication.matchedCount)", detail: "PDFs matched to projects"),
                    StatCard(title: "Missing projects", value: "\(store.snapshot.publication.missingCount)", detail: "project folders without PDFs"),
                    StatCard(title: "Runs", value: "\(store.runs.count)", detail: "saved command executions")
                ]
            )

            SectionCard(title: "Suggested actions") {
                SuggestedActionRow(
                    title: "Open the plan center",
                    body: "Keep roadmap, backlog, and automation ideas visible while the app evolves.",
                    buttonTitle: "Open",
                    action: { store.select(.planCenter) }
                )
                SuggestedActionRow(
                    title: "Refresh knowledge ops",
                    body: "Rebuild project READMEs, publication tracker data, and dashboards.",
                    buttonTitle: "Open",
                    action: { store.select(.workflow("refresh-knowledge-ops")) }
                )
                SuggestedActionRow(
                    title: "Generate a story brief",
                    body: "Use the article corpus to map related stories and blind spots.",
                    buttonTitle: "Open",
                    action: { store.select(.workflow("article-brain-brief")) }
                )
                SuggestedActionRow(
                    title: "Check publication coverage",
                    body: "See which PDFs are linked and which project folders still need a match.",
                    buttonTitle: "Open",
                    action: { store.select(.publication) }
                )
            }
        }
    }
}

struct WorkspaceDetailView: View {
    @EnvironmentObject private var store: AppStore
    let item: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "Metadata") {
                MetadataGrid(rows: [
                    ("Section", item.section.label),
                    ("Project type", item.projectType.label),
                    ("Lifecycle", item.lifecycleStage),
                    ("Safety", item.safetyPosture.label),
                    ("Path", item.path),
                    ("README", item.readmePath ?? "Missing"),
                    ("AGENTS", item.agentsPath ?? "Missing"),
                    ("Direct files", "\(item.directFileCount)"),
                    ("Direct folders", "\(item.directFolderCount)"),
                    ("Markdown", "\(item.markdownFiles)"),
                    ("PDFs", "\(item.pdfFiles)"),
                    ("Google Docs", "\(item.gdocFiles)")
                ])
            }

            if !item.frontmatter.isEmpty {
                SectionCard(title: "Frontmatter") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.frontmatter.keys.sorted(), id: \.self) { key in
                            KeyValueRow(key: key, value: item.frontmatter[key] ?? "")
                        }
                    }
                }
            }

            if !item.agentsSummary.isEmpty {
                SectionCard(title: "Local rules") {
                    Text(item.agentsSummary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            if !item.subtitle.isEmpty {
                SectionCard(title: "Summary") {
                    Text(item.subtitle)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            SectionCard(title: "Actions") {
                HStack {
                    Button("Open folder") { store.openFolder(for: item) }
                    Button("Open README") { store.openReadme(for: item) }
                    if let agentsURL = item.agentsURL {
                        Button("Open AGENTS") {
                            store.openURL(agentsURL)
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
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "Workflow") {
                MetadataGrid(rows: [
                    ("Category", workflow.category),
                    ("Selection", workflow.selectionRequirement.rawValue),
                    ("Writes", workflow.isWriteAction ? "Yes" : "No"),
                    ("Working dir", workflow.workingDirectoryTemplate)
                ])
                if !workflow.note.isEmpty {
                    Text(workflow.note)
                        .foregroundStyle(AppPalette.subtle)
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
                }
                if workflow.isWriteAction {
                    Text("This workflow writes to the workspace. Confirm the target path before running.")
                        .foregroundStyle(AppPalette.subtle)
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
                    .disabled(store.selectedWorkflow?.id != workflow.id || store.isRunning)
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

    private var previewText: String {
        guard let state = store.selectedInputs[workflow.id] else { return workflow.commandPreview }
        do {
            let resolved = try WorkflowRegistry(workspaceRoot: store.workspaceRoot).resolveCommand(
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

struct PlanningCenterView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
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
                        Button("Open project") {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workflow.label)
            Text(workflow.category)
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
            HStack {
                Button("Open PDF") { store.openURL(story.pdfURL) }
                Button("Open project") { store.openURL(story.projectURL) }
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
            HStack {
                Button("Open project") { store.openURL(project.url) }
                Button("Open README") { store.openURL(project.readmeURL) }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct SuggestedActionRow: View {
    let title: String
    let body: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(body)
                    .foregroundStyle(AppPalette.subtle)
            }
            Spacer()
            Button(buttonTitle, action: action)
        }
        .padding(.vertical, 6)
    }
}

struct EmptyStateView: View {
    let title: String
    let body: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(body)
                .foregroundStyle(AppPalette.subtle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorkspaceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppPalette.card.opacity(0.95), in: Capsule())
            .overlay(Capsule().stroke(AppPalette.border))
            .foregroundStyle(AppPalette.title)
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
