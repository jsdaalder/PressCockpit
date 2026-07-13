import XCTest
@testable import JournalismWorkflowHub

final class WorkflowRegistryTests: XCTestCase {
    func testStandaloneProfileShowsOnlyPortableWorkflows() {
        let registry = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standalone
        )

        let workflows = registry.loadWorkflows(selection: nil)

        XCTAssertFalse(workflows.isEmpty)
        XCTAssertTrue(workflows.allSatisfy { $0.availability == .portable })
    }

    func testStandardProfileIncludesLocalAndPrivateWorkflows() {
        let registry = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standard
        )

        let workflows = registry.loadWorkflows(selection: nil)

        XCTAssertTrue(workflows.contains(where: { $0.availability == .optionalLocal }))
        XCTAssertTrue(workflows.contains(where: { $0.availability == .privateHidden }))
    }

    func testScaffoldProjectDefaultsAreNotJanSpecific() throws {
        let registry = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standard
        )

        let workflow = try XCTUnwrap(registry.allWorkflows().first(where: { $0.id == "scaffold-project" }))
        let ownerDefault = workflow.parameters.first(where: { $0.id == "owner" })?.defaultValue
        let projectTypeDefault = workflow.parameters.first(where: { $0.id == "project_type" })?.defaultValue
        let trimmedUserName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedOwner = trimmedUserName.isEmpty ? "Workspace owner" : trimmedUserName

        XCTAssertEqual(ownerDefault, expectedOwner)
        XCTAssertEqual(projectTypeDefault, "journalism")
        XCTAssertTrue(workflow.parameters.contains(where: { $0.id == "project_root" && ($0.defaultValue?.contains("/Projects/") ?? false) }))
        XCTAssertFalse(workflow.parameters.contains(where: { $0.id == "project_root" && ($0.defaultValue?.contains("new_project") ?? false) }))
    }

    func testScaffoldProjectResolveCommandIncludesProjectTypeArgument() throws {
        let workspaceRoot = URL(fileURLWithPath: "/tmp/workspace")
        let registry = WorkflowRegistry(
            workspaceRoot: workspaceRoot,
            appProfile: .standard
        )

        let workflow = try XCTUnwrap(registry.allWorkflows().first(where: { $0.id == "scaffold-project" }))
        var state = WorkflowParameterState()
        state.applyDefaults(from: workflow.parameters)
        state.textValues["project_root"] = "/tmp/workspace/Projects/2026/data_story"
        state.textValues["title"] = "Data Story"
        state.textValues["owner"] = "Test Owner"
        state.textValues["status"] = "active"
        state.textValues["project_type"] = "data_journalism"
        state.textValues["started"] = "2026-07-12"
        state.textValues["deliverable"] = "A short summary."
        state.textValues["section_answer_1"] = "Main question"
        state.textValues["section_answer_2"] = "Expected pattern"
        state.textValues["section_answer_3"] = "Why data is needed"

        let resolved = try registry.resolveCommand(workflow: workflow, state: state, selection: nil)

        XCTAssertTrue(resolved.arguments.contains("--project-type"))
        XCTAssertTrue(resolved.arguments.contains("data_journalism"))
        XCTAssertTrue(resolved.arguments.contains("--section-answer-1"))
        XCTAssertTrue(resolved.arguments.contains("Main question"))
        XCTAssertTrue(resolved.arguments.contains("--section-answer-2"))
        XCTAssertTrue(resolved.arguments.contains("Expected pattern"))
        XCTAssertTrue(resolved.arguments.contains("--section-answer-3"))
        XCTAssertTrue(resolved.arguments.contains("Why data is needed"))
        XCTAssertEqual(resolved.arguments.first, bundledKnowledgeOpsScriptPath("scaffold_project.py"))
        XCTAssertFalse(resolved.arguments.first?.contains("/tmp/workspace/Resources/knowledge_ops/scripts") ?? true)
    }

    func testRefreshKnowledgeOpsUsesBundledScriptPath() throws {
        let registry = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standard
        )

        let workflow = try XCTUnwrap(registry.allWorkflows().first(where: { $0.id == "refresh-knowledge-ops" }))

        XCTAssertEqual(workflow.argumentsTemplate.first, bundledKnowledgeOpsScriptPath("refresh_knowledge_ops.py"))
        XCTAssertEqual(workflow.requiredPaths.first, bundledKnowledgeOpsScriptPath("refresh_knowledge_ops.py"))
    }
}
