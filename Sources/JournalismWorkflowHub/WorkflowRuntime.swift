import Foundation

struct WorkflowRuntimeEnvironment: Sendable {
    let fileExists: @Sendable (String) -> Bool
    let directoryExists: @Sendable (String) -> Bool
    let executableAvailable: @Sendable (String) -> Bool
    let pythonModuleAvailable: @Sendable (_ executable: String, _ module: String, _ workingDirectory: String) -> Bool
    let readTextFile: @Sendable (_ path: String) -> String?

    static let live = WorkflowRuntimeEnvironment(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        directoryExists: { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        },
        executableAvailable: { executable in
            if executable.contains("/") {
                return FileManager.default.isExecutableFile(atPath: executable)
            }

            let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
            let directories = pathValue.split(separator: ":").map(String.init)
            for directory in directories {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return true
                }
            }
            return false
        },
        pythonModuleAvailable: { executable, module, workingDirectory in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable, "-c", "import \(module)"]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        },
        readTextFile: { path in
            try? String(contentsOfFile: path, encoding: .utf8)
        }
    )
}

enum WorkflowPreflightEvaluator {
    static func evaluate(
        workflow: WorkflowDefinition,
        workspaceRoot: URL,
        selection: WorkspaceItem?,
        state: WorkflowParameterState,
        environment: WorkflowRuntimeEnvironment = .live
    ) -> WorkflowPreflightReport {
        let context = WorkflowRegistry.makeTokenContext(
            workspaceRoot: workspaceRoot,
            selection: selection,
            state: state
        )

        switch workflow.selectionRequirement {
        case .none:
            break
        case .workspaceItem:
            guard selection != nil else {
                return report(
                    status: .needsSelection,
                    summary: "Select a workspace item before running this workflow.",
                    checkedItems: ["Selection requirement: workspace item"],
                    missingItems: ["Selected workspace item"],
                    setupHint: workflow.setupHint
                )
            }
        case .projectRoot:
            guard let selection, selection.isProjectRoot else {
                return report(
                    status: .needsSelection,
                    summary: "Select a project root before running this workflow.",
                    checkedItems: ["Selection requirement: project root"],
                    missingItems: ["Selected project root"],
                    setupHint: workflow.setupHint
                )
            }
        }

        let workingDirectory = WorkflowRegistry.substitute(workflow.workingDirectoryTemplate, context: context, shellMode: false)
        guard !workingDirectory.isEmpty else {
            return report(
                status: .invalidConfiguration,
                summary: "This workflow has no resolved working directory.",
                checkedItems: [],
                missingItems: ["Working directory"],
                setupHint: workflow.setupHint
            )
        }

        guard environment.directoryExists(workingDirectory) else {
            return report(
                status: .missingWorkingDirectory,
                summary: "The workflow working directory does not exist.",
                checkedItems: ["Working directory: \(workingDirectory)"],
                missingItems: [workingDirectory],
                setupHint: workflow.setupHint
            )
        }

        let resolvedExecutable = WorkflowRegistry.substitute(workflow.executableTemplate, context: context, shellMode: false)
        let resolvedExecutables = workflow.requiredExecutables.map {
            WorkflowRegistry.substitute($0, context: context, shellMode: false)
        }
        let executablesToCheck = Array(Set(([resolvedExecutable] + resolvedExecutables).filter { !$0.isEmpty }))

        if let missingExecutable = executablesToCheck.first(where: { !environment.executableAvailable($0) }) {
            return report(
                status: .missingExecutable,
                summary: "A required executable is missing from this machine.",
                checkedItems: executablesToCheck.map { "Executable: \($0)" },
                missingItems: [missingExecutable],
                setupHint: workflow.setupHint
            )
        }

        let requiredPaths = workflow.requiredPaths.map {
            WorkflowRegistry.substitute($0, context: context, shellMode: false)
        }.filter { !$0.isEmpty }

        if let missingPath = requiredPaths.first(where: { !environment.fileExists($0) && !environment.directoryExists($0) }) {
            return report(
                status: .missingRequiredPath,
                summary: "A required file or folder is missing from the workspace.",
                checkedItems: requiredPaths.map { "Path: \($0)" },
                missingItems: [missingPath],
                setupHint: workflow.setupHint
            )
        }

        if let compatibilityReport = scaffoldCompatibilityReportIfNeeded(
            workflow: workflow,
            requiredPaths: requiredPaths,
            environment: environment
        ) {
            return compatibilityReport
        }

        if let missingModule = workflow.requiredPythonModules.first(where: {
            !environment.pythonModuleAvailable(resolvedExecutable, $0, workingDirectory)
        }) {
            return report(
                status: .missingPythonModule,
                summary: "The Python environment for this workflow is incomplete.",
                checkedItems: workflow.requiredPythonModules.map { "Python module: \($0)" },
                missingItems: [missingModule],
                setupHint: workflow.setupHint
            )
        }

        return report(
            status: .ready,
            summary: "This workflow is ready to run.",
            checkedItems: [
                "Working directory: \(workingDirectory)"
            ] + executablesToCheck.map { "Executable: \($0)" } + requiredPaths.map { "Path: \($0)" } + workflow.requiredPythonModules.map { "Python module: \($0)" },
            missingItems: [],
            setupHint: workflow.setupHint
        )
    }

    private static func scaffoldCompatibilityReportIfNeeded(
        workflow: WorkflowDefinition,
        requiredPaths: [String],
        environment: WorkflowRuntimeEnvironment
    ) -> WorkflowPreflightReport? {
        guard workflow.id == "scaffold-project",
              let scriptPath = requiredPaths.first(where: { $0.hasSuffix("scaffold_project.py") }),
              let scriptContents = environment.readTextFile(scriptPath) else {
            return nil
        }

        let requiredFlags = [
            "--activity-state",
            "--workflow-stage",
            "--inactive-reason",
            "--section-answer-1",
            "--section-answer-2",
            "--section-answer-3"
        ]
        let missingFlags = requiredFlags.filter { !scriptContents.contains($0) }
        guard !missingFlags.isEmpty else {
            return nil
        }

        return report(
            status: .invalidConfiguration,
            summary: "The bundled scaffold script is outdated.",
            checkedItems: ["Path: \(scriptPath)"],
            missingItems: missingFlags,
            setupHint: "Rebuild or reinstall the app so the bundled scaffold script matches the current workflow contract."
        )
    }

    private static func report(
        status: WorkflowPreflightStatus,
        summary: String,
        checkedItems: [String],
        missingItems: [String],
        setupHint: String?
    ) -> WorkflowPreflightReport {
        WorkflowPreflightReport(
            status: status,
            summary: summary,
            checkedItems: checkedItems,
            missingItems: missingItems,
            setupHint: setupHint
        )
    }
}
