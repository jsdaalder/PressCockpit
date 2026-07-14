import XCTest
@testable import JournalismWorkflowHub

final class WorkflowPreflightEvaluatorTests: XCTestCase {
    func testNeedsSelectionWhenProjectRootWorkflowHasNoSelection() {
        let workflow = makeWorkflow(selectionRequirement: .projectRoot)

        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            selection: nil,
            state: WorkflowParameterState(),
            environment: .passing
        )

        XCTAssertEqual(report.status, .needsSelection)
        XCTAssertFalse(report.isRunnable)
    }

    func testMissingRequiredPathBlocksWorkflow() {
        let workflow = makeWorkflow(requiredPaths: ["{{workspace_root}}/Resources/tool.py"])

        let environment = WorkflowRuntimeEnvironment(
            fileExists: { _ in false },
            directoryExists: { path in path == "/tmp/workspace" },
            executableAvailable: { _ in true },
            pythonModuleAvailable: { _, _, _ in true },
            readTextFile: { _ in nil }
        )

        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            selection: nil,
            state: WorkflowParameterState(),
            environment: environment
        )

        XCTAssertEqual(report.status, .missingRequiredPath)
        XCTAssertEqual(report.missingItems, ["/tmp/workspace/Resources/tool.py"])
    }

    func testMissingPythonModuleBlocksWorkflow() {
        let workflow = makeWorkflow(
            runtimeKind: .pythonModule,
            requiredPaths: [],
            requiredPythonModules: ["article_brain"]
        )

        let environment = WorkflowRuntimeEnvironment(
            fileExists: { _ in true },
            directoryExists: { _ in true },
            executableAvailable: { _ in true },
            pythonModuleAvailable: { _, _, _ in false },
            readTextFile: { _ in nil }
        )

        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            selection: nil,
            state: WorkflowParameterState(),
            environment: environment
        )

        XCTAssertEqual(report.status, .missingPythonModule)
        XCTAssertEqual(report.missingItems, ["article_brain"])
    }

    func testReadyWorkflowPassesAllChecks() {
        let workflow = makeWorkflow(
            requiredExecutables: ["python3"],
            requiredPaths: ["{{workspace_root}}/Resources/tool.py"]
        )

        let environment = WorkflowRuntimeEnvironment(
            fileExists: { path in path == "/tmp/workspace/Resources/tool.py" },
            directoryExists: { path in path == "/tmp/workspace" },
            executableAvailable: { executable in executable == "python3" },
            pythonModuleAvailable: { _, _, _ in true },
            readTextFile: { _ in nil }
        )

        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            selection: nil,
            state: WorkflowParameterState(),
            environment: environment
        )

        XCTAssertEqual(report.status, .ready)
        XCTAssertTrue(report.isRunnable)
    }

    func testOutdatedScaffoldScriptBlocksWorkflowBeforeRun() {
        let workflow = makeWorkflow(
            id: "scaffold-project",
            requiredPaths: ["{{workspace_root}}/Resources/knowledge_ops/scripts/scaffold_project.py"]
        )

        let environment = WorkflowRuntimeEnvironment(
            fileExists: { path in path == "/tmp/workspace/Resources/knowledge_ops/scripts/scaffold_project.py" },
            directoryExists: { _ in true },
            executableAvailable: { _ in true },
            pythonModuleAvailable: { _, _, _ in true },
            readTextFile: { _ in
                """
                parser.add_argument("--project-type")
                parser.add_argument("--draft")
                """
            }
        )

        let report = WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            selection: nil,
            state: WorkflowParameterState(),
            environment: environment
        )

        XCTAssertEqual(report.status, .invalidConfiguration)
        XCTAssertEqual(report.summary, "The bundled scaffold script is outdated.")
        XCTAssertEqual(report.missingItems, ["--activity-state", "--workflow-stage", "--inactive-reason", "--section-answer-1", "--section-answer-2", "--section-answer-3"])
        XCTAssertFalse(report.isRunnable)
    }

    private func makeWorkflow(
        id: String = "demo",
        runtimeKind: WorkflowRuntimeKind = .pythonScript,
        selectionRequirement: WorkflowSelectionRequirement = .none,
        requiredExecutables: [String] = ["python3"],
        requiredPaths: [String] = [],
        requiredPythonModules: [String] = []
    ) -> WorkflowDefinition {
        WorkflowDefinition(
            id: id,
            label: "Demo workflow",
            description: "Test workflow",
            category: "Tests",
            availability: .portable,
            runtimeKind: runtimeKind,
            workingDirectoryTemplate: "{{workspace_root}}",
            kind: .direct,
            executableTemplate: "python3",
            argumentsTemplate: ["script.py"],
            shellCommandTemplate: nil,
            parameters: [],
            selectionRequirement: selectionRequirement,
            isWriteAction: false,
            expectedArtifacts: [],
            requiredExecutables: requiredExecutables,
            requiredPaths: requiredPaths,
            requiredPythonModules: requiredPythonModules,
            setupHint: "Install dependencies.",
            note: ""
        )
    }
}

private extension WorkflowRuntimeEnvironment {
    static let passing = WorkflowRuntimeEnvironment(
        fileExists: { _ in true },
        directoryExists: { _ in true },
        executableAvailable: { _ in true },
        pythonModuleAvailable: { _, _, _ in true },
        readTextFile: { _ in nil }
    )
}
