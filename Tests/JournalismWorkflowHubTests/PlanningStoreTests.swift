import XCTest
@testable import JournalismWorkflowHub

final class PlanningStoreTests: XCTestCase {
    func testLoadsPlanningDocsFromWorkspace() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = tmp.appendingPathComponent("Projects/2026/journalism_workflow_hub_plan/docs")
        let processDocs = docs.appendingPathComponent("process")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: processDocs, withIntermediateDirectories: true, attributes: nil)

        let readme = tmp.appendingPathComponent("Projects/2026/journalism_workflow_hub_plan/README.md")
        try """
        ---
        type: project
        project: journalism_workflow_hub_plan
        ---

        # Journalism Workflow Hub Plan

        This project tracks the product and architecture plan.
        """.write(to: readme, atomically: true, encoding: .utf8)

        try """
        # Roadmap

        The planning center keeps roadmap, backlog, and decisions visible.
        """.write(to: docs.appendingPathComponent("roadmap.md"), atomically: true, encoding: .utf8)

        try """
        # Backlog

        - add a plan center screen
        - add automation reminders
        """.write(to: docs.appendingPathComponent("backlog.md"), atomically: true, encoding: .utf8)

        try """
        # Planning Workflow

        Use backlog for ideas, current priorities for active work, and verification before closeout.
        """.write(to: processDocs.appendingPathComponent("planning_workflow.md"), atomically: true, encoding: .utf8)

        let snapshot = PlanningStore(workspaceRoot: tmp, profile: .standard).load()

        XCTAssertEqual(snapshot.projectTitle, "Journalism Workflow Hub Plan")
        XCTAssertEqual(snapshot.docs.map(\.title), ["Roadmap", "Backlog", "Planning Workflow"])
        XCTAssertEqual(snapshot.docs.first?.summary, "The planning center keeps roadmap, backlog, and decisions visible.")
    }

    func testStandaloneProfileSkipsPrivatePlanningWorkspace() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let snapshot = PlanningStore(workspaceRoot: tmp, profile: .standalone).load()

        XCTAssertEqual(snapshot.projectTitle, "Plan Center")
        XCTAssertTrue(snapshot.docs.isEmpty)
        XCTAssertTrue(snapshot.projectPath.isEmpty)
    }

    func testIgnoresRepoLocalPlanningPointerCopy() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = tmp.appendingPathComponent("Projects/2026/journalism_workflow_hub_plan/docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true, attributes: nil)

        let readme = tmp.appendingPathComponent("Projects/2026/journalism_workflow_hub_plan/README.md")
        try """
        ---
        type: project
        project: journalism_workflow_hub_plan_repo_pointer
        status: archived
        ---

        # Repo-Local Planning Pointer

        This folder is only a pointer copy.
        """.write(to: readme, atomically: true, encoding: .utf8)

        try """
        # Roadmap

        This should not load.
        """.write(to: docs.appendingPathComponent("roadmap.md"), atomically: true, encoding: .utf8)

        let snapshot = PlanningStore(workspaceRoot: tmp, profile: .standard).load()

        XCTAssertEqual(snapshot.projectTitle, "Plan Center")
        XCTAssertTrue(snapshot.docs.isEmpty)
        XCTAssertTrue(snapshot.projectPath.isEmpty)
    }
}
