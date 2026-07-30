import XCTest
@testable import JournalismWorkflowHub

@MainActor
final class AppStoreCatalogQueryTests: XCTestCase {
    func testWorkspaceAndOverviewReadsUseCatalogBackedSnapshotWhenAvailable() throws {
        let workspaceRoot = try makeWorkspaceRoot(projectTitle: "Live Story")
        let liveSnapshot = WorkspaceScanner(workspaceRoot: workspaceRoot).scan()
        let liveItem = try XCTUnwrap(liveSnapshot.items.first)
        let catalogItem = WorkspaceItem(
            id: liveItem.id,
            section: liveItem.section,
            path: liveItem.path,
            readmePath: liveItem.readmePath,
            agentsPath: liveItem.agentsPath,
            title: "Catalog Story",
            summary: "Catalog-backed summary",
            agentsSummary: liveItem.agentsSummary,
            frontmatter: liveItem.frontmatter,
            googleDriveFolderURL: liveItem.googleDriveFolderURL,
            projectType: liveItem.projectType,
            displayStateLabel: liveItem.displayStateLabel,
            safetyPosture: liveItem.safetyPosture,
            directFileCount: liveItem.directFileCount,
            directFolderCount: liveItem.directFolderCount,
            markdownFiles: liveItem.markdownFiles,
            pdfFiles: liveItem.pdfFiles,
            gdocFiles: liveItem.gdocFiles,
            csvFiles: liveItem.csvFiles,
            xlsxFiles: liveItem.xlsxFiles,
            documents: liveItem.documents
        )
        let catalogSnapshot = WorkspaceSnapshot(
            scannedAt: liveSnapshot.scannedAt,
            items: [catalogItem],
            publication: liveSnapshot.publication
        )
        let catalog = StubWorkspaceCatalog(snapshot: catalogSnapshot)

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            catalog: catalog
        )

        XCTAssertEqual(store.snapshot.items.first?.title, "Live Story")
        XCTAssertEqual(catalog.replaceCallCount, 1)
        XCTAssertEqual(store.filteredWorkspaceItems.first?.title, "Catalog Story")
        XCTAssertEqual(store.firstWorkspaceItem?.title, "Catalog Story")
        XCTAssertEqual(store.overviewProjectSummaries.first?.item.title, "Catalog Story")

        store.select(.workspace(liveItem.id))
        XCTAssertEqual(store.selectedWorkspaceItem?.title, "Catalog Story")
        XCTAssertEqual(store.workspaceItem(for: liveItem.id)?.summary, "Catalog-backed summary")
    }

    func testWorkspaceReadsFallBackToLiveSnapshotWhenCatalogLoadReturnsNil() throws {
        let workspaceRoot = try makeWorkspaceRoot(projectTitle: "Live Story")
        let catalog = StubWorkspaceCatalog(snapshot: nil)

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            catalog: catalog
        )

        XCTAssertEqual(catalog.replaceCallCount, 1)
        XCTAssertEqual(store.filteredWorkspaceItems.first?.title, "Live Story")
        XCTAssertEqual(store.firstWorkspaceItem?.title, "Live Story")

        let liveItem = try XCTUnwrap(store.snapshot.items.first)
        store.select(.workspace(liveItem.id))
        XCTAssertEqual(store.selectedWorkspaceItem?.title, "Live Story")
        XCTAssertEqual(store.overviewProjectSummaries.first?.item.title, "Live Story")
    }

    private func makeWorkspaceRoot(projectTitle: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/demo_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: \(projectTitle)
        status: active
        project_type: journalism
        started: 2026-07-06
        deliverable: Story
        safety: unknown
        ---

        # \(projectTitle)

        A project used to test catalog-backed workspace queries.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        return tmp
    }
}

private final class StubWorkspaceCatalog: WorkspaceCataloging {
    let snapshot: WorkspaceSnapshot?
    private(set) var replaceCallCount = 0

    init(snapshot: WorkspaceSnapshot?) {
        self.snapshot = snapshot
    }

    func load() -> WorkspaceCatalog? {
        guard let snapshot else { return nil }
        return WorkspaceCatalog(
            version: 1,
            workspaceRootPath: "",
            storedAt: .now,
            snapshot: snapshot,
            records: []
        )
    }

    func loadSnapshot() -> WorkspaceSnapshot? {
        snapshot
    }

    func replace(with snapshot: WorkspaceSnapshot) {
        replaceCallCount += 1
    }
}
