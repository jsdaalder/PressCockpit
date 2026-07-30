import XCTest
@testable import JournalismWorkflowHub

final class WorkspaceQueryStoreTests: XCTestCase {
    func testQueryUsesCanonicalProjectStateTagsInsteadOfCompatibilityStatusWhenExplicitStateExists() {
        let item = makeProject(
            id: "explicit-state-project",
            title: "Explicit State Project",
            frontmatter: [
                "status": "on_hold",
                "activity_state": "active",
                "workflow_stage": "lead"
            ]
        )
        let store = WorkspaceQueryStore(snapshot: WorkspaceSnapshot(scannedAt: .now, items: [item], publication: .empty))

        XCTAssertEqual(store.filteredItems(matching: "lead").map(\.id), [item.id])
        XCTAssertEqual(store.filteredItems(matching: "active").map(\.id), [item.id])
        XCTAssertTrue(store.filteredItems(matching: "on_hold").isEmpty)
    }

    func testQueryKeepsLegacyStatusSearchForProjectWithoutExplicitState() {
        let item = makeProject(
            id: "legacy-status-project",
            title: "Legacy Status Project",
            frontmatter: [
                "status": "on_hold"
            ]
        )
        let store = WorkspaceQueryStore(snapshot: WorkspaceSnapshot(scannedAt: .now, items: [item], publication: .empty))

        XCTAssertEqual(store.filteredItems(matching: "on_hold").map(\.id), [item.id])
        XCTAssertEqual(store.filteredItems(matching: "waiting").map(\.id), [item.id])
    }

    private func makeProject(
        id: String,
        title: String,
        frontmatter: [String: String]
    ) -> WorkspaceItem {
        let mergedFrontmatter = [
            "type": "project",
            "project": title,
            "project_type": "journalism",
            "started": "2026-07-30",
            "owner": "Jan"
        ].merging(frontmatter) { _, new in new }

        return WorkspaceItem(
            id: id,
            section: .projects,
            path: "/tmp/\(id)",
            readmePath: "/tmp/\(id)/README.md",
            agentsPath: nil,
            title: title,
            summary: "Summary for \(title)",
            agentsSummary: "",
            frontmatter: mergedFrontmatter,
            googleDriveFolderURL: nil,
            projectType: .journalism,
            displayStateLabel: "Active",
            safetyPosture: .unknown,
            directFileCount: 1,
            directFolderCount: 1,
            markdownFiles: 1,
            pdfFiles: 0,
            gdocFiles: 0,
            csvFiles: 0,
            xlsxFiles: 0,
            documents: []
        )
    }
}
