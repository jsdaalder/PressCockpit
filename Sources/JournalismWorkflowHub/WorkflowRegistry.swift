import Foundation

struct WorkflowRegistry {
    let workspaceRoot: URL
    let appProfile: AppProfile

    func loadWorkflows(selection: WorkspaceItem?) -> [WorkflowDefinition] {
        allWorkflows().filter { workflow in
            switch appProfile {
            case .standard:
                return true
            case .standalone:
                return workflow.availability == .portable
            }
        }.sorted {
            if $0.category != $1.category {
                return $0.category < $1.category
            }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    func allWorkflows() -> [WorkflowDefinition] {
        var workflows = portableBuiltInWorkflows()
        workflows.append(contentsOf: localBuiltInWorkflows())
        workflows.append(contentsOf: loadCustomWorkflows())
        return workflows
    }

    private func portableBuiltInWorkflows() -> [WorkflowDefinition] {
        [
            WorkflowDefinition(
                id: "open-workspace-root",
                label: "Open workspace root",
                description: "Reveal the current workspace root in Finder.",
                category: "Utilities",
                availability: .portable,
                runtimeKind: .shell,
                workingDirectoryTemplate: "{{workspace_root}}",
                kind: .direct,
                executableTemplate: "/usr/bin/open",
                argumentsTemplate: ["{{workspace_root}}"],
                shellCommandTemplate: nil,
                parameters: [],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [],
                requiredExecutables: ["/usr/bin/open"],
                requiredPaths: ["{{workspace_root}}"],
                requiredPythonModules: [],
                setupHint: "This utility works in both standard and standalone mode.",
                note: "Useful for checking the sample workspace or the current root on another Mac."
            ),
            WorkflowDefinition(
                id: "open-selected-folder",
                label: "Open selected folder",
                description: "Reveal the selected workspace item in Finder.",
                category: "Utilities",
                availability: .portable,
                runtimeKind: .shell,
                workingDirectoryTemplate: "{{workspace_root}}",
                kind: .direct,
                executableTemplate: "/usr/bin/open",
                argumentsTemplate: ["{{selected_path}}"],
                shellCommandTemplate: nil,
                parameters: [],
                selectionRequirement: .workspaceItem,
                isWriteAction: false,
                expectedArtifacts: [],
                requiredExecutables: ["/usr/bin/open"],
                requiredPaths: ["{{selected_path}}"],
                requiredPythonModules: [],
                setupHint: "Select a workspace item before running this utility.",
                note: "A portable navigation helper for the standalone pilot."
            )
        ]
    }

    private func localBuiltInWorkflows() -> [WorkflowDefinition] {
        let root = workspaceRoot.path
        let defaultProjectPath = "\(root)/Projects/\(isoYear())/untitled_project"
        let defaultOwner = nonEmpty(NSFullUserName()) ?? "Workspace owner"
        let missingBundledScriptRoot = "__missing_bundle__/knowledge_ops/scripts"
        let bundledScriptPath: (String) -> String = { name in
            bundledKnowledgeOpsScriptPath(name) ?? "\(missingBundledScriptRoot)/\(name)"
        }

        return [
            WorkflowDefinition(
                id: "scaffold-project",
                label: "Scaffold project",
                description: "Create a new reporting project with README, AGENTS, and docs overview.",
                category: "Workspace",
                availability: .optionalLocal,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    bundledScriptPath("scaffold_project.py"),
                    "--project-root", "{{project_root}}",
                    "--title", "{{title}}",
                    "--owner", "{{owner}}",
                    "--activity-state", "{{activity_state}}",
                    "--workflow-stage", "{{workflow_stage}}",
                    "--inactive-reason", "{{inactive_reason}}",
                    "--project-type", "{{project_type}}",
                    "--dossier", "{{dossier}}",
                    "--started", "{{started}}",
                    "--deliverable", "{{deliverable}}",
                    "--section-answer-1", "{{section_answer_1}}",
                    "--section-answer-2", "{{section_answer_2}}",
                    "--section-answer-3", "{{section_answer_3}}",
                    "--topics", "{{topics}}",
                    "--entities", "{{entities}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "project_root", label: "Project root", kind: .path, helpText: "Absolute path to the new project folder.", defaultValue: defaultProjectPath, required: true),
                    .init(id: "title", label: "Title", kind: .text, helpText: "Human-facing project title.", defaultValue: "New story", required: true),
                    .init(id: "owner", label: "Owner", kind: .text, helpText: "Project owner.", defaultValue: defaultOwner),
                    .init(id: "activity_state", label: "Activity state", kind: .choice, helpText: "Canonical project-state field for active versus inactive work.", defaultValue: "active", choices: ["active", "inactive"]),
                    .init(id: "workflow_stage", label: "Workflow stage", kind: .choice, helpText: "Canonical newsroom phase written into README frontmatter.", defaultValue: "lead", choices: ["lead", "feasibility_study", "active_investigation", "drafting_fact_checking", "desk_head_review", "eindredactie", "published"]),
                    .init(id: "inactive_reason", label: "Inactive reason", kind: .choice, helpText: "Canonical inactive reason when the project is not active.", defaultValue: "", choices: ["", "waiting", "finished", "discarded", "parked"]),
                    .init(id: "project_type", label: "Project type", kind: .choice, helpText: "Project classification written into README frontmatter.", defaultValue: "journalism", choices: ["journalism", "data_journalism", "tooling", "general"]),
                    .init(id: "dossier", label: "Dossier", kind: .text, helpText: "Optional dossier slug to link from the new project.", defaultValue: ""),
                    .init(id: "started", label: "Started", kind: .text, helpText: "Date in YYYY-MM-DD.", defaultValue: isoDate()),
                    .init(id: "deliverable", label: "Deliverable", kind: .text, helpText: "Story or product description.", defaultValue: ""),
                    .init(id: "section_answer_1", label: "Section answer 1", kind: .text, helpText: "First structured answer for the starter README.", defaultValue: ""),
                    .init(id: "section_answer_2", label: "Section answer 2", kind: .text, helpText: "Second structured answer for the starter README.", defaultValue: ""),
                    .init(id: "section_answer_3", label: "Section answer 3", kind: .text, helpText: "Third structured answer for the starter README.", defaultValue: ""),
                    .init(id: "topics", label: "Topics", kind: .multiline, helpText: "Space or comma separated topic slugs.", defaultValue: "", expandsToMultipleArguments: true),
                    .init(id: "entities", label: "Entities", kind: .multiline, helpText: "Space or comma separated entity slugs.", defaultValue: "", expandsToMultipleArguments: true)
                ],
                selectionRequirement: .none,
                isWriteAction: true,
                expectedArtifacts: [
                    "{{project_root}}/README.md",
                    "{{project_root}}/AGENTS.md",
                    "{{project_root}}/docs/docs_overview.md"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    bundledScriptPath("scaffold_project.py")
                ],
                requiredPythonModules: [],
                setupHint: "Rebuild or reinstall the app so the bundled knowledge-ops scripts are available.",
                note: "Creates a clean starter structure for a new investigation."
            ),
            WorkflowDefinition(
                id: "refresh-knowledge-ops",
                label: "Refresh knowledge ops",
                description: "Rebuild queues, project READMEs, publication trackers, dashboards, and the vault note index.",
                category: "Workspace",
                availability: .optionalLocal,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    bundledScriptPath("refresh_knowledge_ops.py"),
                    "--years", "{{years}}",
                    "--backfill-title-stubs",
                    "--overwrite"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "years", label: "Years", kind: .multiline, helpText: "Space separated years to include.", defaultValue: "2022 2023 2024 2025 2026", required: true, expandsToMultipleArguments: true)
                ],
                selectionRequirement: .none,
                isWriteAction: true,
                expectedArtifacts: [
                    "Resources/knowledge_ops/index/refresh_knowledge_ops_summary.json",
                    "Resources/knowledge_ops/index/publication_tracker.csv",
                    "Resources/knowledge_ops/index/publication_index.md"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    bundledScriptPath("refresh_knowledge_ops.py")
                ],
                requiredPythonModules: [],
                setupHint: "Rebuild or reinstall the app so the bundled knowledge-ops scripts are available.",
                note: "Best used after publication syncs or when project READMEs need a rebuild."
            ),
            WorkflowDefinition(
                id: "build-project-readme",
                label: "Build project README",
                description: "Refresh one project README from local evidence and cached Google Docs.",
                category: "Project",
                availability: .optionalLocal,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    bundledScriptPath("build_project_readme.py"),
                    "--project-root", "{{selected_path}}",
                    "--write-readme"
                ],
                shellCommandTemplate: nil,
                parameters: [],
                selectionRequirement: .projectRoot,
                isWriteAction: true,
                expectedArtifacts: [
                    "{{selected_readme_path}}"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    bundledScriptPath("build_project_readme.py"),
                    "{{selected_path}}"
                ],
                requiredPythonModules: [],
                setupHint: "Select a project root and make sure the bundled knowledge-ops scripts are present in the app build.",
                note: "Requires a selected project or dossier folder."
            ),
            WorkflowDefinition(
                id: "refresh-project-google-doc-prep",
                label: "Refresh project Google Doc prep",
                description: "Refresh the selected project README, ensure Google Doc cache placeholders exist, and update the global fetch backlog.",
                category: "Documents",
                availability: .optionalLocal,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    bundledScriptPath("refresh_knowledge_ops.py"),
                    "--project-root", "{{selected_path}}",
                    "--overwrite",
                    "--skip-publication-tracker",
                    "--skip-publication-artifacts",
                    "--skip-publication-metadata",
                    "--skip-note-index"
                ],
                shellCommandTemplate: nil,
                parameters: [],
                selectionRequirement: .projectRoot,
                isWriteAction: true,
                expectedArtifacts: [
                    "{{selected_readme_path}}",
                    "Resources/knowledge_ops/index/gdoc_fetch_queue.csv",
                    "Resources/knowledge_ops/index/gdoc_fetch_queue.json",
                    "Resources/knowledge_ops/index/refresh_knowledge_ops_summary.json"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    bundledScriptPath("refresh_knowledge_ops.py"),
                    "{{selected_path}}"
                ],
                requiredPythonModules: [],
                setupHint: "This prepares local cache placeholders and updates the Google Doc fetch backlog, but it does not fetch Google Docs from the network by itself.",
                note: "Best used after adding new root `.gdoc` pointers or when cache status looks out of date."
            ),
            WorkflowDefinition(
                id: "build-gdoc-fetch-queue",
                label: "Build Google Doc fetch queue",
                description: "Rebuild the backlog of root Google Doc pointers that still need local cache content.",
                category: "Documents",
                availability: .optionalLocal,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    bundledScriptPath("build_gdoc_fetch_queue.py"),
                    "--years", "{{years}}",
                    "--write-index"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "years", label: "Years", kind: .multiline, helpText: "Space separated years to include in the fetch backlog.", defaultValue: "2022 2023 2024 2025 2026", required: true, expandsToMultipleArguments: true)
                ],
                selectionRequirement: .none,
                isWriteAction: true,
                expectedArtifacts: [
                    "Resources/knowledge_ops/index/gdoc_fetch_queue.csv",
                    "Resources/knowledge_ops/index/gdoc_fetch_queue.json"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    bundledScriptPath("build_gdoc_fetch_queue.py")
                ],
                requiredPythonModules: [],
                setupHint: "This workflow uses the app’s bundled knowledge-ops scripts. It rebuilds the fetch backlog only; it does not export Google Docs itself.",
                note: "Useful when you want a current list of uncached or placeholder-only root Google Docs."
            ),
            WorkflowDefinition(
                id: "build-publication-tracker",
                label: "Build publication tracker",
                description: "Rebuild the PDF-to-project publication mapping and dashboards.",
                category: "Archive",
                availability: .optionalLocal,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    bundledScriptPath("build_publication_tracker.py")
                ],
                shellCommandTemplate: nil,
                parameters: [],
                selectionRequirement: .none,
                isWriteAction: true,
                expectedArtifacts: [
                    "Resources/knowledge_ops/index/publication_tracker.csv",
                    "Resources/knowledge_ops/index/project_publication_coverage.csv",
                    "Areas/knowledge_base/dashboards/publication_index.md"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    bundledScriptPath("build_publication_tracker.py")
                ],
                requiredPythonModules: [],
                setupHint: "This workflow uses the app’s bundled publication scripts. Rebuild or reinstall the app if they are missing.",
                note: "Use this when published PDFs or project links have changed."
            ),
            WorkflowDefinition(
                id: "article-brain-brief",
                label: "Article Brain brief",
                description: "Generate a story briefing from the PDF corpus.",
                category: "Research",
                availability: .privateHidden,
                runtimeKind: .pythonModule,
                workingDirectoryTemplate: "\(root)/Resources/article_brain",
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "-m", "article_brain.cli.main", "brief", "{{pitch}}", "--top-k", "{{top_k}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "pitch", label: "Pitch", kind: .multiline, helpText: "Story pitch or reporting question.", defaultValue: "", required: true),
                    .init(id: "top_k", label: "Top K", kind: .number, helpText: "How many related stories to include.", defaultValue: "6", required: false)
                ],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    "Resources/article_brain"
                ],
                requiredPythonModules: ["article_brain"],
                setupHint: "Make sure the local article-brain package and its Python dependencies are installed inside the workspace environment.",
                note: "Works from the local article corpus index."
            ),
            WorkflowDefinition(
                id: "article-brain-headlines",
                label: "Article Brain headlines",
                description: "Generate corpus-grounded headline options.",
                category: "Research",
                availability: .privateHidden,
                runtimeKind: .pythonModule,
                workingDirectoryTemplate: "\(root)/Resources/article_brain",
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "-m", "article_brain.cli.main", "headlines", "{{abstract}}", "--tone", "{{tone}}", "--top-k", "{{top_k}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "abstract", label: "Abstract", kind: .multiline, helpText: "Story summary or headline target.", defaultValue: "", required: true),
                    .init(id: "tone", label: "Tone", kind: .choice, helpText: "Headline tone.", defaultValue: "onderzoekend", choices: ["onderzoekend", "urgent", "analysis", "explainer"]),
                    .init(id: "top_k", label: "Top K", kind: .number, helpText: "How many corpus hits to use.", defaultValue: "5")
                ],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    "Resources/article_brain"
                ],
                requiredPythonModules: ["article_brain"],
                setupHint: "Make sure the local article-brain package and its Python dependencies are installed inside the workspace environment.",
                note: "Useful for iterative headline exploration."
            ),
            WorkflowDefinition(
                id: "traces-ask",
                label: "TRACES ask",
                description: "Ask a natural-language question against the TRACES workspace.",
                category: "Research",
                availability: .privateHidden,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: "\(root)/Projects/2026/traces/traces_analysis",
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "scripts/ask.py", "{{question}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "question", label: "Question", kind: .multiline, helpText: "Question to ask the dataset.", defaultValue: "", required: true)
                ],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [
                    "Projects/2026/traces/traces_analysis/outputs/answers",
                    "Projects/2026/traces/traces_analysis/outputs/tables",
                    "Projects/2026/traces/traces_analysis/outputs/queries"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    "Projects/2026/traces/traces_analysis/scripts/ask.py"
                ],
                requiredPythonModules: [],
                setupHint: "Make sure the TRACES analysis project and its Python environment are available in the workspace.",
                note: "Best for newsroom-style queries over the TRACES data product."
            ),
            WorkflowDefinition(
                id: "traces-run-query",
                label: "TRACES run query",
                description: "Run a named TRACES query spec.",
                category: "Research",
                availability: .privateHidden,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: "\(root)/Projects/2026/traces/traces_analysis",
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "scripts/run_query.py", "{{query_name}}", "--dataset", "{{dataset}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "query_name", label: "Query name", kind: .text, helpText: "Named query in the TRACES query catalog.", defaultValue: "route_rankings", required: true),
                    .init(id: "dataset", label: "Dataset", kind: .text, helpText: "Dataset name, for example transport_routes.", defaultValue: "transport_routes", required: true)
                ],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [
                    "Projects/2026/traces/traces_analysis/outputs/answers",
                    "Projects/2026/traces/traces_analysis/outputs/tables",
                    "Projects/2026/traces/traces_analysis/outputs/queries"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    "Projects/2026/traces/traces_analysis/scripts/run_query.py"
                ],
                requiredPythonModules: [],
                setupHint: "Make sure the TRACES analysis project and its Python environment are available in the workspace.",
                note: "Use when you already know the structured query you want."
            ),
            WorkflowDefinition(
                id: "voedselcrisis-evidence-query",
                label: "Evidence query",
                description: "Query the dossier evidence database.",
                category: "Dossier",
                availability: .privateHidden,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: "\(root)/Areas/voedselcrisis_2027",
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "scripts/query_evidence.py",
                    "--text", "{{text}}",
                    "--theme", "{{theme}}",
                    "--limit", "{{limit}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "text", label: "Text", kind: .multiline, helpText: "Query terms.", defaultValue: "", required: true),
                    .init(id: "theme", label: "Theme", kind: .text, helpText: "Optional dossier theme slug.", defaultValue: ""),
                    .init(id: "limit", label: "Limit", kind: .number, helpText: "Max results.", defaultValue: "5")
                ],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [
                    "Areas/voedselcrisis_2027/data/indices",
                    "Areas/voedselcrisis_2027/analysis"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    "Areas/voedselcrisis_2027/scripts/query_evidence.py"
                ],
                requiredPythonModules: [],
                setupHint: "This dossier workflow needs the local dossier scripts and Python environment in place.",
                note: "Useful for cross-source reporting questions."
            ),
            WorkflowDefinition(
                id: "event-scanner-report",
                label: "Event scanner report",
                description: "Inspect the local event scanner database and generate a report.",
                category: "Utilities",
                availability: .privateHidden,
                runtimeKind: .pythonScript,
                workingDirectoryTemplate: "\(root)/Projects/event-scanner",
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "./tools/run_event_scanner.py", "report", "--db", "./data/db/event_scanner.sqlite"
                ],
                shellCommandTemplate: nil,
                parameters: [],
                selectionRequirement: .none,
                isWriteAction: false,
                expectedArtifacts: [
                    "Projects/event-scanner/data/outputs"
                ],
                requiredExecutables: ["python3"],
                requiredPaths: [
                    "Projects/event-scanner/tools/run_event_scanner.py",
                    "Projects/event-scanner/data/db/event_scanner.sqlite"
                ],
                requiredPythonModules: [],
                setupHint: "Make sure the event-scanner project and its local database exist before running this report.",
                note: "Quick status check for the event-scanner tool."
            )
        ]
    }

    private func loadCustomWorkflows() -> [WorkflowDefinition] {
        let candidates = [
            workspaceRoot.appendingPathComponent("Resources/Overig/journalism_workflow_hub/workflows.json"),
            appSupportDirectory().appendingPathComponent("workflows.json")
        ]

        var definitions: [WorkflowDefinition] = []
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let data = try? Data(contentsOf: candidate),
                  let presets = try? JSONDecoder().decode([CustomWorkflowPreset].self, from: data) else {
                continue
            }

            definitions.append(contentsOf: presets.map { preset in
                WorkflowDefinition(
                    id: preset.id,
                    label: preset.label,
                    description: preset.description,
                    category: preset.category,
                    availability: preset.availability ?? .optionalLocal,
                    runtimeKind: preset.runtimeKind ?? .shell,
                    workingDirectoryTemplate: preset.workingDirectory,
                    kind: .shell,
                    executableTemplate: "/bin/zsh",
                    argumentsTemplate: ["-lc", preset.shellCommand],
                    shellCommandTemplate: preset.shellCommand,
                    parameters: [],
                    selectionRequirement: preset.selectionRequirement,
                    isWriteAction: preset.isWriteAction,
                    expectedArtifacts: preset.expectedArtifacts,
                    requiredExecutables: preset.requiredExecutables ?? ["/bin/zsh"],
                    requiredPaths: preset.requiredPaths ?? [],
                    requiredPythonModules: preset.requiredPythonModules ?? [],
                    setupHint: preset.setupHint,
                    note: preset.note
                )
            })
        }

        return definitions
    }

    func resolveCommand(
        workflow: WorkflowDefinition,
        state: WorkflowParameterState,
        selection: WorkspaceItem?
    ) throws -> ResolvedWorkflowCommand {
        switch workflow.selectionRequirement {
        case .none:
            break
        case .workspaceItem:
            if selection == nil {
                throw WorkflowError.selectionRequired
            }
        case .projectRoot:
            guard let selection, selection.isProjectRoot else {
                throw WorkflowError.projectRootRequired
            }
        }

        let context = Self.makeTokenContext(
            workspaceRoot: workspaceRoot,
            selection: selection,
            state: state
        )

        let workingDirectory = Self.substitute(workflow.workingDirectoryTemplate, context: context, shellMode: false)
        let parameterLookup = Dictionary(uniqueKeysWithValues: workflow.parameters.map { ($0.id, $0) })

        switch workflow.kind {
        case .direct:
            let executable = Self.substitute(workflow.executableTemplate, context: context, shellMode: false)
            let arguments = resolvedArguments(
                workflow.argumentsTemplate,
                context: context,
                parameterLookup: parameterLookup
            )
            let preview = ([executable] + arguments).map(Self.shellEscape).joined(separator: " ")
            let artifacts = workflow.expectedArtifacts.map { Self.substitute($0, context: context, shellMode: false) }
            return ResolvedWorkflowCommand(
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                commandPreview: preview,
                estimatedOutputs: artifacts
            )
        case .shell:
            guard let template = workflow.shellCommandTemplate else {
                throw WorkflowError.invalidConfiguration("Shell workflow is missing a shell command.")
            }
            let command = Self.substitute(template, context: context, shellMode: true)
            let preview = "/bin/zsh -lc \(Self.shellEscape(command))"
            let artifacts = workflow.expectedArtifacts.map { Self.substitute($0, context: context, shellMode: false) }
            return ResolvedWorkflowCommand(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                workingDirectory: workingDirectory,
                commandPreview: preview,
                estimatedOutputs: artifacts
            )
        }
    }

    static func makeTokenContext(
        workspaceRoot: URL,
        selection: WorkspaceItem?,
        state: WorkflowParameterState
    ) -> TokenContext {
        TokenContext(
            workspaceRoot: workspaceRoot.path,
            selectedPath: selection?.path,
            selectedReadmePath: selection?.readmePath,
            selectedTitle: selection?.title,
            state: state
        )
    }

    static func substitute(_ template: String, context: TokenContext, shellMode: Bool) -> String {
        var result = template
        let replacements: [String: String] = [
            "{{workspace_root}}": context.workspaceRoot,
            "{{selected_path}}": context.selectedPath ?? "",
            "{{selected_readme_path}}": context.selectedReadmePath ?? "",
            "{{selected_title}}": context.selectedTitle ?? ""
        ]

        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: shellMode ? Self.shellEscape(value) : value)
        }

        for (key, value) in context.state.textValues {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: shellMode ? Self.shellEscape(value) : value)
        }
        for (key, value) in context.state.booleanValues {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value ? "true" : "false")
        }

        return result
    }

    private func resolvedArguments(
        _ templates: [String],
        context: TokenContext,
        parameterLookup: [String: WorkflowParameterSpec]
    ) -> [String] {
        var arguments: [String] = []
        for template in templates {
            guard let token = exactTokenIdentifier(in: template),
                  let spec = parameterLookup[token] else {
                arguments.append(Self.substitute(template, context: context, shellMode: false))
                continue
            }

            let value = Self.substitute(template, context: context, shellMode: false)
            if spec.expandsToMultipleArguments {
                let pieces = splitList(value)
                if pieces.isEmpty {
                    continue
                }
                arguments.append(contentsOf: pieces)
            } else {
                arguments.append(value)
            }
        }
        return arguments
    }

    private func exactTokenIdentifier(in template: String) -> String? {
        guard template.hasPrefix("{{"), template.hasSuffix("}}") else { return nil }
        let inner = template.dropFirst(2).dropLast(2)
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func splitList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",\n\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func shellEscape(_ string: String) -> String {
        if string.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-:=,@")
        if string.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return string
        }
        return "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func appSupportDirectory() -> URL {
        journalismWorkflowHubSupportDirectory()
    }
}

enum WorkflowError: LocalizedError {
    case selectionRequired
    case projectRootRequired
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .selectionRequired:
            return "This workflow requires a selected workspace item."
        case .projectRootRequired:
            return "This workflow requires a selected project root."
        case .invalidConfiguration(let message):
            return message
        }
    }
}

struct TokenContext {
    let workspaceRoot: String
    let selectedPath: String?
    let selectedReadmePath: String?
    let selectedTitle: String?
    let state: WorkflowParameterState
}

private func isoDate() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: .now)
}

private func isoYear() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy"
    return formatter.string(from: .now)
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
