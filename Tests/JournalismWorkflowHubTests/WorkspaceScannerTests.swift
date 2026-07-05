import XCTest
@testable import JournalismWorkflowHub

final class WorkspaceScannerTests: XCTestCase {
    func testParsesFrontmatterAndTitle() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        let readme = project.appendingPathComponent("README.md")
        let text = """
        ---
        type: project
        project: demo_story
        status: active
        started: 2026-07-05
        ---

        # Demo Story

        The first paragraph is the summary for this project.
        """
        try text.write(to: readme, atomically: true, encoding: .utf8)

        let scanner = WorkspaceScanner(workspaceRoot: tmp)
        let snapshot = scanner.scan()

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items.first?.title, "Demo Story")
        XCTAssertEqual(snapshot.items.first?.frontmatter["status"], "active")
        XCTAssertEqual(snapshot.items.first?.projectType, .journalism)
        XCTAssertEqual(snapshot.items.first?.lifecycleStage, "Active")
        XCTAssertEqual(snapshot.items.first?.safetyPosture, .publishable)
    }

    func testReadsAgentsAndClassifiesToolingProjects() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/workflow_hub")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        status: active
        ---

        # Workflow Hub

        Native SwiftUI launcher for the reporting workspace.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        # AGENTS

        Keep this repository local-first and privacy-aware before sharing exports.
        """.write(to: project.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        let snapshot = WorkspaceScanner(workspaceRoot: tmp).scan()
        let item = try XCTUnwrap(snapshot.items.first)

        XCTAssertEqual(item.projectType, .tooling)
        XCTAssertEqual(item.safetyPosture, .localSensitive)
        XCTAssertEqual(item.agentsSummary, "Keep this repository local-first and privacy-aware before sharing exports.")
        XCTAssertEqual(item.agentsPath, project.appendingPathComponent("AGENTS.md").path)
    }

    func testClassifiesAreasAsOngoingInternalWork() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let area = tmp.appendingPathComponent("Areas/food_watch")
        try FileManager.default.createDirectory(at: area, withIntermediateDirectories: true, attributes: nil)

        try """
        # Food Watch

        Ongoing responsibility for monitoring policy changes.
        """.write(to: area.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let snapshot = WorkspaceScanner(workspaceRoot: tmp).scan()
        let item = try XCTUnwrap(snapshot.items.first)

        XCTAssertEqual(item.projectType, .area)
        XCTAssertEqual(item.lifecycleStage, "Ongoing")
        XCTAssertEqual(item.safetyPosture, .internalOnly)
    }

    func testPublicationCsvIsParsed() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let index = tmp.appendingPathComponent("Resources/knowledge_ops/index")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true, attributes: nil)

        let tracker = """
        pdf_title,pdf_path,published_year,published_year_source,date_line,headline,article_note_path,match_status,matched_project_year,matched_project_slug,matched_project_path,matched_project_readme,matched_project_title,match_score,match_basis,match_candidate,candidate_2_slug,candidate_2_score,candidate_3_slug,candidate_3_score,exists_in_legacy_corpus,review_decision,review_confirmed_project_slug,review_notes,review_year_override
        Demo PDF,/tmp/demo.pdf,2026,filesystem,,,matched,2026,demo,/tmp/project,/tmp/project/README.md,Demo Project,1.0,manual_confirmed,Demo Project,,,,,yes,confirmed,,
        """
        try tracker.write(to: index.appendingPathComponent("publication_tracker.csv"), atomically: true, encoding: .utf8)

        let coverage = """
        project_year,project_slug,project_path,readme_path,readme_title,readme_quality,matched_pdf_count,matched_pdf_titles,published_status_from_pdfs
        2026,demo,/tmp/project,/tmp/project/README.md,Demo Project,high,1,Demo PDF,published
        """
        try coverage.write(to: index.appendingPathComponent("project_publication_coverage.csv"), atomically: true, encoding: .utf8)

        let store = PublicationStore(workspaceRoot: tmp)
        let snapshot = store.load()

        XCTAssertEqual(snapshot.matchedCount, 1)
        XCTAssertEqual(snapshot.missingCount, 0)
        XCTAssertEqual(snapshot.storiesByYear["2026"]?.first?.pdfTitle, "Demo PDF")
    }
}
