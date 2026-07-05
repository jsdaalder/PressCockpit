import XCTest
@testable import JournalismWorkflowHub

final class PlanningStoreTests: XCTestCase {
    func testLoadsPlanningDocsFromWorkspace() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = tmp.appendingPathComponent("Projects/2026/journalism_workflow_hub_plan/docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true, attributes: nil)

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

        let snapshot = PlanningStore(workspaceRoot: tmp).load()

        XCTAssertEqual(snapshot.projectTitle, "Journalism Workflow Hub Plan")
        XCTAssertEqual(snapshot.docs.map(\.title), ["Roadmap", "Backlog"])
        XCTAssertEqual(snapshot.docs.first?.summary, "The planning center keeps roadmap, backlog, and decisions visible.")
    }
}
