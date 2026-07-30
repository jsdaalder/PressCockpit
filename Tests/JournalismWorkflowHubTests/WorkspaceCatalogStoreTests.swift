import XCTest
@testable import JournalismWorkflowHub

final class WorkspaceCatalogStoreTests: XCTestCase {
    func testCatalogRoundTripsSnapshotAndRecords() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRoot = tmp.appendingPathComponent("workspace")
        let supportRoot = tmp.appendingPathComponent("support")
        let project = workspaceRoot.appendingPathComponent("Projects/2026/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Demo Story
        status: on_hold
        activity_state: inactive
        workflow_stage: feasibility_study
        inactive_reason: waiting
        project_type: journalism
        safety: unknown
        ---

        # Demo Story

        Summary paragraph for the demo project.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let snapshot = WorkspaceScanner(workspaceRoot: workspaceRoot).scan()
        let store = WorkspaceCatalogStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        store.replace(with: snapshot)

        let catalog = try XCTUnwrap(store.load())
        XCTAssertEqual(catalog.version, 1)
        XCTAssertEqual(catalog.workspaceRootPath, workspaceRoot.path)
        XCTAssertEqual(catalog.snapshot.items.count, 1)
        XCTAssertEqual(catalog.records.count, 1)
        XCTAssertEqual(catalog.records.first?.projectType, .journalism)
        XCTAssertEqual(catalog.records.first?.lifecycleStage, "Inactive · Feasibility study · Waiting")
        XCTAssertEqual(catalog.records.first?.activityState, .inactive)
        XCTAssertEqual(catalog.records.first?.workflowStage, .feasibilityStudy)
        XCTAssertEqual(catalog.records.first?.inactiveReason, .waiting)
        XCTAssertEqual(catalog.records.first?.compatibilityStatus, .onHold)
        XCTAssertEqual(catalog.records.first?.safetyPosture, .unknown)
        XCTAssertNotNil(catalog.records.first?.readmeModifiedAt)
    }

    func testCatalogIgnoresSnapshotForDifferentWorkspaceRoot() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspaceRootA = tmp.appendingPathComponent("workspace-a")
        let workspaceRootB = tmp.appendingPathComponent("workspace-b")
        let supportRoot = tmp.appendingPathComponent("support")
        let project = workspaceRootA.appendingPathComponent("Projects/2026/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Demo Story
        status: active
        project_type: journalism
        safety: unknown
        ---

        # Demo Story

        Summary paragraph for the demo project.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let snapshot = WorkspaceScanner(workspaceRoot: workspaceRootA).scan()
        WorkspaceCatalogStore(
            workspaceRoot: workspaceRootA,
            supportDirectory: supportRoot
        ).replace(with: snapshot)

        let mismatchedStore = WorkspaceCatalogStore(
            workspaceRoot: workspaceRootB,
            supportDirectory: supportRoot
        )
        XCTAssertNil(mismatchedStore.load())
        XCTAssertNil(mismatchedStore.loadSnapshot())
    }
}
