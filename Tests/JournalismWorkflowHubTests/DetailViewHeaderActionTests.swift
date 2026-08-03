import XCTest
@testable import JournalismWorkflowHub

final class DetailViewHeaderActionTests: XCTestCase {
    func testHeaderActionMenuIsHiddenOnOverviewAndCapture() {
        XCTAssertFalse(shouldShowHeaderActionMenu(for: .overview, workspaceItem: nil))
        XCTAssertFalse(shouldShowHeaderActionMenu(for: .capture, workspaceItem: nil))
    }

    func testHeaderActionMenuIsHiddenOnProjectPages() {
        let project = makeWorkspaceItem(
            id: "project",
            section: .projects,
            frontmatter: ["type": "project", "project": "Demo project"],
            projectType: .journalism
        )

        XCTAssertFalse(shouldShowHeaderActionMenu(for: .workspace(project.id), workspaceItem: project))
    }

    func testHeaderActionMenuStaysVisibleOnNonProjectWorkspacePagesAndOtherDestinations() {
        let area = makeWorkspaceItem(
            id: "area",
            section: .areas,
            frontmatter: ["type": "area", "project": "Coverage area"],
            projectType: .area
        )

        XCTAssertTrue(shouldShowHeaderActionMenu(for: .workspace(area.id), workspaceItem: area))
        XCTAssertTrue(shouldShowHeaderActionMenu(for: .publication, workspaceItem: nil))
        XCTAssertTrue(shouldShowHeaderActionMenu(for: .planCenter, workspaceItem: nil))
        XCTAssertTrue(shouldShowHeaderActionMenu(for: .workflow("scaffold-project"), workspaceItem: nil))
        XCTAssertTrue(shouldShowHeaderActionMenu(for: .run("run-1"), workspaceItem: nil))
    }

    private func makeWorkspaceItem(
        id: String,
        section: WorkspaceSection,
        frontmatter: [String: String],
        projectType: WorkspaceProjectType
    ) -> WorkspaceItem {
        WorkspaceItem(
            id: id,
            section: section,
            path: "/tmp/\(id)",
            readmePath: "/tmp/\(id)/README.md",
            agentsPath: nil,
            title: frontmatter["project"] ?? id,
            summary: "",
            agentsSummary: "",
            frontmatter: frontmatter,
            googleDriveFolderURL: nil,
            projectType: projectType,
            displayStateLabel: "",
            safetyPosture: .unknown,
            directFileCount: 0,
            directFolderCount: 0,
            markdownFiles: 1,
            pdfFiles: 0,
            gdocFiles: 0,
            csvFiles: 0,
            xlsxFiles: 0,
            documents: []
        )
    }
}
