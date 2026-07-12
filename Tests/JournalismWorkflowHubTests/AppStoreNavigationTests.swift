import XCTest
@testable import JournalismWorkflowHub

@MainActor
final class AppStoreNavigationTests: XCTestCase {
    func testBackAndForwardTrackVisitedPages() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        XCTAssertEqual(store.selection, .overview)
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)

        store.select(.workspace(project.id))
        store.select(.publication)

        XCTAssertEqual(store.selection, .publication)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)

        store.goBack()

        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)

        store.goBack()

        XCTAssertEqual(store.selection, .overview)
        XCTAssertFalse(store.canNavigateBack)
        XCTAssertTrue(store.canNavigateForward)

        store.goForward()
        XCTAssertEqual(store.selection, .workspace(project.id))

        store.goForward()
        XCTAssertEqual(store.selection, .publication)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)
    }

    func testSelectingNewPageClearsForwardHistory() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        store.select(.workspace(project.id))
        store.select(.publication)
        store.goBack()

        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertTrue(store.canNavigateForward)

        store.select(.overview)

        XCTAssertEqual(store.selection, .overview)
        XCTAssertTrue(store.canNavigateBack)
        XCTAssertFalse(store.canNavigateForward)

        store.goForward()
        XCTAssertEqual(store.selection, .overview)
    }

    func testReusingExistingScaffoldProjectRoutesIntoPostCreateState() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first)

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .now
        )

        let postCreateState = try XCTUnwrap(store.scaffoldPostCreateState)
        XCTAssertEqual(postCreateState.mode, .reused)
        XCTAssertEqual(postCreateState.projectRoot, project.path)
        XCTAssertTrue(postCreateState.shouldAutoPromptForDocuments)
        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertEqual(store.statusMessage, "Using existing project. Add documents now.")
    }

    private func makeWorkspaceRoot() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/demo_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Demo Story
        status: active
        project_type: journalism
        started: 2026-07-06
        deliverable: Story
        ---

        # Demo Story

        A project used to test app navigation history.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        # AGENTS

        Keep this project local-first during tests.
        """.write(to: project.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        return tmp
    }
}
