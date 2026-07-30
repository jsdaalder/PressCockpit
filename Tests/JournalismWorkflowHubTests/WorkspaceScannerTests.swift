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
        project: Demo Story
        status: active
        project_type: journalism
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
        XCTAssertEqual(snapshot.items.first?.activityState, .active)
        XCTAssertEqual(snapshot.items.first?.workflowStage, .activeInvestigation)
        XCTAssertNil(snapshot.items.first?.inactiveReason)
        XCTAssertEqual(snapshot.items.first?.projectType, .journalism)
        XCTAssertEqual(snapshot.items.first?.displayStateLabel, "Active · Investigation")
        XCTAssertEqual(snapshot.items.first?.safetyPosture, .unknown)
    }

    func testParsesIndentedFrontmatterFromExistingScaffoldedReadme() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/indented_demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
                ---
                type: project
                project: Indented Demo Story
                status: active
                project_type: journalism
                started: 2026-07-14
                ---

                # Indented Demo Story

                Summary paragraph for an older scaffolded README.
                """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(item.title, "Indented Demo Story")
        XCTAssertEqual(item.frontmatter["project"], "Indented Demo Story")
        XCTAssertEqual(item.projectType, .journalism)
        XCTAssertEqual(item.summary, "Summary paragraph for an older scaffolded README.")
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
        XCTAssertEqual(
            URL(fileURLWithPath: item.agentsPath ?? "").standardizedFileURL.path,
            project.appendingPathComponent("AGENTS.md").standardizedFileURL.path
        )
    }

    func testExplicitFrontmatterOverridesHeuristicsAndNormalizesAliases() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/data_desk")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Data Desk
        status: on_hold
        project_type: data-journalism
        safety: publishable
        ---

        # Data Desk

        Native SwiftUI launcher for the reporting workspace.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        # AGENTS

        Keep this repository local-first and privacy-aware before sharing exports.
        """.write(to: project.appendingPathComponent("AGENTS.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(item.projectType, .dataJournalism)
        XCTAssertEqual(item.activityState, .inactive)
        XCTAssertEqual(item.workflowStage, .activeInvestigation)
        XCTAssertEqual(item.inactiveReason, .waiting)
        XCTAssertEqual(item.displayStateLabel, "Inactive · Investigation · Waiting")
        XCTAssertEqual(item.safetyPosture, .publishableReviewed)
    }

    func testExplicitProjectStateFrontmatterOverridesLegacyStatusFallback() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/foi_waiting")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: FOI Waiting
        activity_state: inactive
        workflow_stage: feasibility_study
        inactive_reason: waiting
        status: on_hold
        project_type: journalism
        ---

        # FOI Waiting

        Waiting for public-records response before the next step.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(item.activityState, .inactive)
        XCTAssertEqual(item.workflowStage, .feasibilityStudy)
        XCTAssertEqual(item.inactiveReason, .waiting)
        XCTAssertEqual(item.displayStateLabel, "Inactive · Feasibility study · Waiting")
    }

    func testHumanizesSlugLikeFrontmatterProjectTitle() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/olieprijzen_dalen_weer")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: olieprijzen_dalen_weer
        status: active
        ---

        # olieprijzen_dalen_weer

        A short but valid project summary that should not become the title.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(item.title, "Olieprijzen dalen weer")
    }

    func testExtractsDriveFolderURLAndHumanizesFallbackSlug() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/wur_voedselzekerheid_rapport")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        status: active
        drive_folder_url: https://drive.google.com/drive/folders/abc123
        ---
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(item.title, "Wur voedselzekerheid rapport")
        XCTAssertEqual(item.googleDriveFolderURL, "https://drive.google.com/drive/folders/abc123")
    }

    func testSummarySkipsMarkdownSubheadingAndUsesFirstParagraph() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/summary_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Summary Story
        status: active
        ---

        # Summary Story

        ## Short Summary / Intro

        This is the real summary paragraph that should appear in the active project card instead of the markdown subheading.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(
            item.summary,
            "This is the real summary paragraph that should appear in the active project card instead of the markdown subheading."
        )
    }

    func testSummarySkipsHtmlCommentsAndCommandLists() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/summary_cleanup_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Summary Cleanup Story
        status: active
        ---

        <!-- publication_status:start -->
        1. `python3 scripts/extract_knmi_sunrise_sundown.py`

        This is the first real editorial summary paragraph and it should survive the scanner cleanup rules.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(
            item.summary,
            "This is the first real editorial summary paragraph and it should survive the scanner cleanup rules."
        )
    }

    func testParsesRootDocumentsAndGoogleDocCacheState() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/document_story")
        let cacheRoot = project.appendingPathComponent("docs/_derived/google_docs")
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Document Story
        status: active
        project_type: journalism
        ---

        # Document Story

        A reporting project with a draft and local research note.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        try """
        {"doc_id":"abc123","resource_key":"","email":"jan@example.com"}
        """.write(to: project.appendingPathComponent("Artikel.gdoc"), atomically: true, encoding: .utf8)

        try """
        ---
        title: Artikel
        doc_id: abc123
        cached_on: 2026-07-06
        cache_mode: fetched_body
        ---

        Cached draft body.
        """.write(to: cacheRoot.appendingPathComponent("artikel.md"), atomically: true, encoding: .utf8)

        try "Local reporting notes.".write(to: project.appendingPathComponent("Research.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)
        XCTAssertEqual(item.documents.count, 2)

        let draft = try XCTUnwrap(item.documents.first(where: { $0.fileExtension == "gdoc" }))
        XCTAssertEqual(draft.provider, .googleDocPointer)
        XCTAssertEqual(draft.role, .draft)
        XCTAssertEqual(draft.cacheState, .cachedText)
        XCTAssertEqual(draft.cachedOn, "2026-07-06")
        XCTAssertEqual(draft.docID, "abc123")
        XCTAssertEqual(draft.freshness(referenceDate: fixedDate("2026-07-08")), .fresh)

        let research = try XCTUnwrap(item.documents.first(where: { $0.title == "Research" }))
        XCTAssertEqual(research.provider, .localFile)
        XCTAssertEqual(research.role, .research)
        XCTAssertEqual(research.cacheState, .localFile)
        XCTAssertEqual(research.freshness(referenceDate: fixedDate("2026-07-08")), .localFile)
    }

    func testDocumentFreshnessFlagsNeedsFetchAndStaleCache() {
        let stale = WorkspaceDocument(
            id: "stale",
            path: "/tmp/Artikel.gdoc",
            title: "Artikel",
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: .draft,
            cacheState: .cachedText,
            externalURL: nil,
            docID: "abc",
            cachePath: "/tmp/artikel.md",
            cachedOn: "2026-06-01"
        )
        let needsFetch = WorkspaceDocument(
            id: "missing",
            path: "/tmp/Research.gdoc",
            title: "Research",
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: .research,
            cacheState: .placeholder,
            externalURL: nil,
            docID: "def",
            cachePath: "/tmp/research.md",
            cachedOn: "2026-07-06"
        )

        XCTAssertEqual(stale.freshness(referenceDate: fixedDate("2026-07-06")), .stale)
        XCTAssertEqual(needsFetch.freshness(referenceDate: fixedDate("2026-07-06")), .needsFetch)
    }

    func testLegacyProjectWithoutExplicitSafetyFallsBackConservatively() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/legacy_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Legacy Story
        status: active
        ---

        # Legacy Story

        Journalism project for a reporting workspace with a deliverable.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let item = try XCTUnwrap(WorkspaceScanner(workspaceRoot: tmp).scan().items.first)

        XCTAssertEqual(item.projectType, .journalism)
        XCTAssertEqual(item.safetyPosture, .unknown)
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
        XCTAssertEqual(item.displayStateLabel, "Ongoing")
        XCTAssertEqual(item.safetyPosture, .internalOnly)
    }

    func testPublicationCsvIsParsed() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let index = tmp.appendingPathComponent("Resources/knowledge_ops/index")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true, attributes: nil)

        let tracker = """
        pdf_title,pdf_path,published_year,published_year_source,date_line,headline,article_note_path,match_status,matched_project_year,matched_project_slug,matched_project_path,matched_project_readme,matched_project_title,match_score,match_basis,match_candidate,candidate_2_slug,candidate_2_score,candidate_3_slug,candidate_3_score,exists_in_legacy_corpus,review_decision,review_confirmed_project_slug,review_notes,review_year_override
        Demo PDF,/tmp/demo.pdf,2026,filesystem,,,,matched,2026,demo,/tmp/project,/tmp/project/README.md,Demo Project,1.0,manual_confirmed,,,,,,,yes,confirmed,,,
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

    private func fixedDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? .distantPast
    }
}
