import Foundation

struct WorkflowRegistry {
    let workspaceRoot: URL

    func loadWorkflows(selection: WorkspaceItem?) -> [WorkflowDefinition] {
        var workflows = builtInWorkflows()
        workflows.append(contentsOf: loadCustomWorkflows())

        return workflows.sorted {
            if $0.category != $1.category {
                return $0.category < $1.category
            }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private func builtInWorkflows() -> [WorkflowDefinition] {
        let root = workspaceRoot.path
        let knowledgeOps = "Resources/knowledge_ops/scripts"
        let articleBrain = "Resources/article_brain"
        let traces = "Projects/2026/traces/traces_analysis"
        let voedselcrisis = "Areas/voedselcrisis_2027"
        let eventScanner = "Projects/event-scanner"

        return [
            WorkflowDefinition(
                id: "scaffold-project",
                label: "Scaffold project",
                description: "Create a new reporting project with README, AGENTS, and docs overview.",
                category: "Workspace",
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "\(knowledgeOps)/scaffold_project.py",
                    "--project-root", "{{project_root}}",
                    "--title", "{{title}}",
                    "--owner", "{{owner}}",
                    "--status", "{{status}}",
                    "--started", "{{started}}",
                    "--deliverable", "{{deliverable}}",
                    "--topics", "{{topics}}",
                    "--entities", "{{entities}}"
                ],
                shellCommandTemplate: nil,
                parameters: [
                    .init(id: "project_root", label: "Project root", kind: .path, helpText: "Absolute path to the new project folder.", defaultValue: "\(root)/Projects/2026/new_story", required: true),
                    .init(id: "title", label: "Title", kind: .text, helpText: "Human-facing project title.", defaultValue: "New story", required: true),
                    .init(id: "owner", label: "Owner", kind: .text, helpText: "Project owner.", defaultValue: "Jan Daalder"),
                    .init(id: "status", label: "Status", kind: .choice, helpText: "Project state.", defaultValue: "active", choices: ["active", "scaffold_demo", "published", "paused"]),
                    .init(id: "started", label: "Started", kind: .text, helpText: "Date in YYYY-MM-DD.", defaultValue: isoDate()),
                    .init(id: "deliverable", label: "Deliverable", kind: .text, helpText: "Story or product description.", defaultValue: ""),
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
                note: "Creates a clean starter structure for a new investigation."
            ),
            WorkflowDefinition(
                id: "refresh-knowledge-ops",
                label: "Refresh knowledge ops",
                description: "Rebuild queues, project READMEs, publication trackers, dashboards, and the vault note index.",
                category: "Workspace",
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "\(knowledgeOps)/refresh_knowledge_ops.py",
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
                note: "Best used after publication syncs or when project READMEs need a rebuild."
            ),
            WorkflowDefinition(
                id: "build-project-readme",
                label: "Build project README",
                description: "Refresh one project README from local evidence and cached Google Docs.",
                category: "Project",
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "\(knowledgeOps)/build_project_readme.py",
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
                note: "Requires a selected project or dossier folder."
            ),
            WorkflowDefinition(
                id: "build-publication-tracker",
                label: "Build publication tracker",
                description: "Rebuild the PDF-to-project publication mapping and dashboards.",
                category: "Archive",
                workingDirectoryTemplate: root,
                kind: .direct,
                executableTemplate: "python3",
                argumentsTemplate: [
                    "\(knowledgeOps)/build_publication_tracker.py"
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
                note: "Use this when published PDFs or project links have changed."
            ),
            WorkflowDefinition(
                id: "article-brain-brief",
                label: "Article Brain brief",
                description: "Generate a story briefing from the PDF corpus.",
                category: "Research",
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
                note: "Works from the local article corpus index."
            ),
            WorkflowDefinition(
                id: "article-brain-headlines",
                label: "Article Brain headlines",
                description: "Generate corpus-grounded headline options.",
                category: "Research",
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
                note: "Useful for iterative headline exploration."
            ),
            WorkflowDefinition(
                id: "traces-ask",
                label: "TRACES ask",
                description: "Ask a natural-language question against the TRACES workspace.",
                category: "Research",
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
                note: "Best for newsroom-style queries over the TRACES data product."
            ),
            WorkflowDefinition(
                id: "traces-run-query",
                label: "TRACES run query",
                description: "Run a named TRACES query spec.",
                category: "Research",
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
                note: "Use when you already know the structured query you want."
            ),
            WorkflowDefinition(
                id: "voedselcrisis-evidence-query",
                label: "Evidence query",
                description: "Query the dossier evidence database.",
                category: "Dossier",
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
                note: "Useful for cross-source reporting questions."
            ),
            WorkflowDefinition(
                id: "event-scanner-report",
                label: "Event scanner report",
                description: "Inspect the local event scanner database and generate a report.",
                category: "Utilities",
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
                    workingDirectoryTemplate: preset.workingDirectory,
                    kind: .shell,
                    executableTemplate: "/bin/zsh",
                    argumentsTemplate: ["-lc", preset.shellCommand],
                    shellCommandTemplate: preset.shellCommand,
                    parameters: [],
                    selectionRequirement: preset.selectionRequirement,
                    isWriteAction: preset.isWriteAction,
                    expectedArtifacts: preset.expectedArtifacts,
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

        let context = TokenContext(
            workspaceRoot: workspaceRoot.path,
            selectedPath: selection?.path,
            selectedReadmePath: selection?.readmePath,
            selectedTitle: selection?.title,
            state: state
        )

        let workingDirectory = substitute(workflow.workingDirectoryTemplate, context: context, shellMode: false)
        let parameterLookup = Dictionary(uniqueKeysWithValues: workflow.parameters.map { ($0.id, $0) })

        switch workflow.kind {
        case .direct:
            let executable = substitute(workflow.executableTemplate, context: context, shellMode: false)
            let arguments = resolvedArguments(
                workflow.argumentsTemplate,
                context: context,
                parameterLookup: parameterLookup
            )
            let preview = ([executable] + arguments).map(shellEscape).joined(separator: " ")
            let artifacts = workflow.expectedArtifacts.map { substitute($0, context: context, shellMode: false) }
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
            let command = substitute(template, context: context, shellMode: true)
            let preview = "/bin/zsh -lc \(shellEscape(command))"
            let artifacts = workflow.expectedArtifacts.map { substitute($0, context: context, shellMode: false) }
            return ResolvedWorkflowCommand(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                workingDirectory: workingDirectory,
                commandPreview: preview,
                estimatedOutputs: artifacts
            )
        }
    }

    private func substitute(_ template: String, context: TokenContext, shellMode: Bool) -> String {
        var result = template
        let replacements: [String: String] = [
            "{{workspace_root}}": context.workspaceRoot,
            "{{selected_path}}": context.selectedPath ?? "",
            "{{selected_readme_path}}": context.selectedReadmePath ?? "",
            "{{selected_title}}": context.selectedTitle ?? ""
        ]

        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: shellMode ? shellEscape(value) : value)
        }

        for (key, value) in context.state.textValues {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: shellMode ? shellEscape(value) : value)
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
                arguments.append(substitute(template, context: context, shellMode: false))
                continue
            }

            let value = substitute(template, context: context, shellMode: false)
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

    private func shellEscape(_ string: String) -> String {
        if string.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-:=,@")
        if string.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return string
        }
        return "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private func appSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JournalismWorkflowHub", isDirectory: true)
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

private struct TokenContext {
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
