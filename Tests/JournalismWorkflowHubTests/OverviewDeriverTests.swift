import XCTest
@testable import JournalismWorkflowHub

final class OverviewDeriverTests: XCTestCase {
    func testSummaryPreviewFormatterLimitsCollapsedPreviewToTenWords() {
        let longSummary = """
        De timinganalyse is bewust beperkt tot 2021-2025 omdat de gekoppelde KNMI tabel alleen voor deze jaren is opgebouwd.
        """

        XCTAssertEqual(
            SummaryPreviewFormatter.wordLimitedPreview(longSummary, limit: 10),
            "De timinganalyse is bewust beperkt tot 2021-2025 omdat de gekoppelde…"
        )
    }

    func testSummaryPreviewFormatterKeepsShortSummaryUntouched() {
        let shortSummary = "Kort, duidelijk en meteen bruikbaar."

        XCTAssertEqual(
            SummaryPreviewFormatter.wordLimitedPreview(shortSummary, limit: 10),
            shortSummary
        )
    }

    func testActiveProjectsExcludeToolingAndInactiveStatusesAndCapAtFour() {
        let activeUnknown = makeProject(
            id: "active-unknown",
            title: "Active Unknown",
            projectType: .journalism,
            status: "active",
            safety: .unknown,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-06"
        )
        let activeClear = makeProject(
            id: "active-clear",
            title: "Active Clear",
            projectType: .dataJournalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Dataset",
            hasAgents: true,
            started: "2026-07-05"
        )
        let activeNeedsBasics = makeProject(
            id: "active-basics",
            title: "Active Basics",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "",
            hasAgents: true,
            started: "2026-07-04"
        )
        let activeNoStarted = makeProject(
            id: "active-no-started",
            title: "Active No Started",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: ""
        )
        let activeFifth = makeProject(
            id: "active-fifth",
            title: "Active Fifth",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-03"
        )
        let toolingProject = makeProject(
            id: "tooling",
            title: "Tooling",
            projectType: .tooling,
            status: "active",
            safety: .localSensitive,
            deliverable: "Tool",
            hasAgents: true,
            started: "2026-07-07"
        )
        let onHoldProject = makeProject(
            id: "on-hold",
            title: "On Hold",
            projectType: .journalism,
            status: "on_hold",
            safety: .unknown,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-08"
        )

        let snapshot = WorkspaceSnapshot(
            scannedAt: .now,
            items: [activeClear, toolingProject, onHoldProject, activeUnknown, activeNeedsBasics, activeNoStarted, activeFifth],
            publication: .empty
        )

        let summaries = OverviewDeriver.projectSummaries(from: snapshot, runs: [])

        XCTAssertEqual(summaries.count, 4)
        XCTAssertEqual(summaries.map(\.item.id), ["active-basics", "active-no-started", "active-unknown", "active-clear"])
    }

    func testFlagPrecedencePrefersLatestFailedRunOverOtherIssues() throws {
        let project = makeProject(
            id: "review",
            title: "Review Project",
            projectType: .journalism,
            status: "active",
            safety: .unknown,
            deliverable: "",
            hasAgents: false,
            started: "2026-07-06"
        )
        let snapshot = WorkspaceSnapshot(
            scannedAt: .now,
            items: [project],
            publication: .empty
        )
        let failedRun = WorkflowRun(
            id: "run-1",
            workflowID: "refresh-knowledge-ops",
            workflowLabel: "Refresh knowledge ops",
            startedAt: "2026-07-06T10-00-00Z",
            finishedAt: "2026-07-06T10-01-00Z",
            exitCode: 1,
            commandPreview: "cmd",
            workingDirectory: "/tmp",
            stdoutPath: "/tmp/stdout",
            stderrPath: "/tmp/stderr",
            manifestPath: "/tmp/manifest",
            artifactPaths: [],
            selectionPath: project.path
        )

        let summary = try XCTUnwrap(OverviewDeriver.projectSummaries(from: snapshot, runs: [failedRun]).first)

        XCTAssertEqual(summary.primaryFlag, "Workflow needs attention")
        XCTAssertEqual(summary.flags, [
            "Workflow needs attention",
            "Project setup incomplete",
            "Needs review before sharing"
        ])
        XCTAssertEqual(summary.displayPrimaryFlag, "Active · Investigation")
        XCTAssertEqual(summary.primaryTarget, .workspace(project.id))
        XCTAssertEqual(summary.primaryButtonTitle, "Open in app")
        XCTAssertEqual(
            summary.nextStep,
            "Open the project and check the latest workflow issue before continuing the reporting."
        )
    }

    func testSuggestedActionsAndOperationsDeduplicateLatestFailedRunScopes() {
        let reviewProject = makeProject(
            id: "review",
            title: "Review",
            projectType: .journalism,
            status: "active",
            safety: .unknown,
            deliverable: "",
            hasAgents: false,
            started: "2026-07-06"
        )
        let clearProject = makeProject(
            id: "clear",
            title: "Clear",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-05"
        )
        let publication = PublicationSnapshot(
            storiesByYear: [:],
            projectsByYear: [:],
            matchedCount: 0,
            missingCount: 3
        )
        let snapshot = WorkspaceSnapshot(
            scannedAt: .now,
            items: [reviewProject, clearProject],
            publication: publication
        )

        let olderFailedRun = WorkflowRun(
            id: "run-older",
            workflowID: "refresh-knowledge-ops",
            workflowLabel: "Refresh knowledge ops",
            startedAt: "2026-07-06T09-00-00Z",
            finishedAt: "2026-07-06T09-01-00Z",
            exitCode: 1,
            commandPreview: "cmd",
            workingDirectory: "/tmp",
            stdoutPath: "/tmp/stdout",
            stderrPath: "/tmp/stderr",
            manifestPath: "/tmp/manifest",
            artifactPaths: [],
            selectionPath: reviewProject.path
        )
        let newerSuccessfulRun = WorkflowRun(
            id: "run-newer",
            workflowID: "refresh-knowledge-ops",
            workflowLabel: "Refresh knowledge ops",
            startedAt: "2026-07-06T10-00-00Z",
            finishedAt: "2026-07-06T10-01-00Z",
            exitCode: 0,
            commandPreview: "cmd",
            workingDirectory: "/tmp",
            stdoutPath: "/tmp/stdout",
            stderrPath: "/tmp/stderr",
            manifestPath: "/tmp/manifest",
            artifactPaths: [],
            selectionPath: reviewProject.path
        )
        let workflowFailedRun = WorkflowRun(
            id: "run-global",
            workflowID: "build-publication-tracker",
            workflowLabel: "Build publication tracker",
            startedAt: "2026-07-06T11-00-00Z",
            finishedAt: "2026-07-06T11-01-00Z",
            exitCode: 1,
            commandPreview: "cmd",
            workingDirectory: "/tmp",
            stdoutPath: "/tmp/stdout",
            stderrPath: "/tmp/stderr",
            manifestPath: "/tmp/manifest",
            artifactPaths: [],
            selectionPath: nil
        )

        let actions = OverviewDeriver.suggestedActions(
            from: snapshot,
            runs: [olderFailedRun, newerSuccessfulRun, workflowFailedRun]
        )
        let operations = OverviewDeriver.operationSummaries(
            from: snapshot,
            runs: [olderFailedRun, newerSuccessfulRun, workflowFailedRun]
        )

        XCTAssertEqual(actions.map(\.count), [1, 1])
        XCTAssertEqual(operations.map(\.count), [1, 1, 3])
    }

    func testProjectSummariesCarryPrimaryDocuments() throws {
        let project = makeProject(
            id: "docs",
            title: "Docs Project",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-06"
        )
        let draft = WorkspaceDocument(
            id: "/tmp/docs/Artikel.gdoc",
            path: "/tmp/docs/Artikel.gdoc",
            title: "Artikel",
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: .draft,
            cacheState: .cachedText,
            externalURL: "https://docs.google.com/document/d/abc/edit",
            docID: "abc",
            cachePath: "/tmp/docs/_derived/google_docs/artikel.md",
            cachedOn: "2026-07-06"
        )
        let draftSnapshot = WorkspaceDocument(
            id: "/tmp/docs/Artikel.md",
            path: "/tmp/docs/Artikel.md",
            title: "Artikel Snapshot",
            fileExtension: "md",
            provider: .localFile,
            role: .draft,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )
        let research = WorkspaceDocument(
            id: "/tmp/docs/Research.md",
            path: "/tmp/docs/Research.md",
            title: "Research",
            fileExtension: "md",
            provider: .localFile,
            role: .research,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )
        let item = WorkspaceItem(
            id: project.id,
            section: project.section,
            path: project.path,
            readmePath: project.readmePath,
            agentsPath: project.agentsPath,
            title: project.title,
            summary: project.summary,
            agentsSummary: project.agentsSummary,
            frontmatter: project.frontmatter,
            googleDriveFolderURL: "https://drive.google.com/drive/folders/project-folder",
            projectType: project.projectType,
            lifecycleStage: project.lifecycleStage,
            safetyPosture: project.safetyPosture,
            directFileCount: project.directFileCount,
            directFolderCount: project.directFolderCount,
            markdownFiles: project.markdownFiles,
            pdfFiles: project.pdfFiles,
            gdocFiles: 1,
            csvFiles: project.csvFiles,
            xlsxFiles: project.xlsxFiles,
            documents: [research, draftSnapshot, draft]
        )

        let summary = try XCTUnwrap(OverviewDeriver.projectSummaries(
            from: WorkspaceSnapshot(scannedAt: .now, items: [item], publication: .empty),
            runs: []
        ).first)

        XCTAssertEqual(summary.primaryDocuments.map(\.title), ["Artikel", "Research"])
    }

    func testCanonicalDraftPrefersGoogleDocOverLocalSnapshotCopy() throws {
        let project = makeProject(
            id: "snapshot",
            title: "Snapshot Project",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-06"
        )
        let pointerDraft = WorkspaceDocument(
            id: "/tmp/snapshot/Artikel.gdoc",
            path: "/tmp/snapshot/Artikel.gdoc",
            title: "Artikel",
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: .draft,
            cacheState: .cachedText,
            externalURL: "https://docs.google.com/document/d/abc/edit",
            docID: "abc",
            cachePath: "/tmp/snapshot/docs/_derived/google_docs/artikel.md",
            cachedOn: "2026-07-06"
        )
        let localSnapshot = WorkspaceDocument(
            id: "/tmp/snapshot/Artikel.md",
            path: "/tmp/snapshot/Artikel.md",
            title: "Artikel",
            fileExtension: "md",
            provider: .localFile,
            role: .draft,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )
        let item = WorkspaceItem(
            id: project.id,
            section: project.section,
            path: project.path,
            readmePath: project.readmePath,
            agentsPath: project.agentsPath,
            title: project.title,
            summary: project.summary,
            agentsSummary: project.agentsSummary,
            frontmatter: project.frontmatter,
            googleDriveFolderURL: nil,
            projectType: project.projectType,
            lifecycleStage: project.lifecycleStage,
            safetyPosture: project.safetyPosture,
            directFileCount: project.directFileCount,
            directFolderCount: project.directFolderCount,
            markdownFiles: project.markdownFiles,
            pdfFiles: project.pdfFiles,
            gdocFiles: 1,
            csvFiles: project.csvFiles,
            xlsxFiles: project.xlsxFiles,
            documents: [localSnapshot, pointerDraft]
        )

        XCTAssertEqual(item.canonicalDraftDocument?.id, pointerDraft.id)
        XCTAssertTrue(item.isLikelyDerivedSnapshot(localSnapshot))
        XCTAssertEqual(item.overviewShortcutDocuments.map(\.title), ["Artikel"])
    }

    func testCanonicalDraftPrefersPromotedGoogleDocOverLocalDocxDraft() {
        let project = makeProject(
            id: "promoted-google-draft",
            title: "Promoted Google Draft",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-06"
        )
        let localDraft = WorkspaceDocument(
            id: "/tmp/promoted-google-draft/Draft - Promoted Google Draft.docx",
            path: "/tmp/promoted-google-draft/Draft - Promoted Google Draft.docx",
            title: "Draft - Promoted Google Draft",
            fileExtension: "docx",
            provider: .localFile,
            role: .draft,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )
        let promotedGoogleDraft = WorkspaceDocument(
            id: "/tmp/promoted-google-draft/Draft.gdoc",
            path: "/tmp/promoted-google-draft/Draft.gdoc",
            title: "Draft",
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: .draft,
            cacheState: .cachedText,
            externalURL: "https://docs.google.com/document/d/abc/edit",
            docID: "abc",
            cachePath: "/tmp/promoted-google-draft/docs/_derived/google_docs/draft.md",
            cachedOn: "2026-07-06"
        )
        let item = WorkspaceItem(
            id: project.id,
            section: project.section,
            path: project.path,
            readmePath: project.readmePath,
            agentsPath: project.agentsPath,
            title: project.title,
            summary: project.summary,
            agentsSummary: project.agentsSummary,
            frontmatter: project.frontmatter,
            googleDriveFolderURL: nil,
            projectType: project.projectType,
            lifecycleStage: project.lifecycleStage,
            safetyPosture: project.safetyPosture,
            directFileCount: project.directFileCount,
            directFolderCount: project.directFolderCount,
            markdownFiles: project.markdownFiles,
            pdfFiles: project.pdfFiles,
            gdocFiles: 1,
            csvFiles: project.csvFiles,
            xlsxFiles: project.xlsxFiles,
            documents: [localDraft, promotedGoogleDraft]
        )

        XCTAssertEqual(item.canonicalDraftDocument?.id, promotedGoogleDraft.id)
    }

    func testCanonicalDraftKeepsLocalAuthoredDraftUntilGoogleDraftWasExplicitlyPromoted() {
        let project = makeProject(
            id: "mixed-draft-ownership",
            title: "Mixed Draft Ownership",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-06"
        )
        let localDraft = WorkspaceDocument(
            id: "/tmp/mixed-draft-ownership/Draft - Mixed Draft Ownership.docx",
            path: "/tmp/mixed-draft-ownership/Draft - Mixed Draft Ownership.docx",
            title: "Draft - Mixed Draft Ownership",
            fileExtension: "docx",
            provider: .localFile,
            role: .draft,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )
        let linkedGoogleDoc = WorkspaceDocument(
            id: "/tmp/mixed-draft-ownership/Artikel.gdoc",
            path: "/tmp/mixed-draft-ownership/Artikel.gdoc",
            title: "Artikel",
            fileExtension: "gdoc",
            provider: .googleDocPointer,
            role: .draft,
            cacheState: .cachedText,
            externalURL: "https://docs.google.com/document/d/abc/edit",
            docID: "abc",
            cachePath: "/tmp/mixed-draft-ownership/docs/_derived/google_docs/artikel.md",
            cachedOn: "2026-07-06"
        )
        let item = WorkspaceItem(
            id: project.id,
            section: project.section,
            path: project.path,
            readmePath: project.readmePath,
            agentsPath: project.agentsPath,
            title: project.title,
            summary: project.summary,
            agentsSummary: project.agentsSummary,
            frontmatter: project.frontmatter,
            googleDriveFolderURL: nil,
            projectType: project.projectType,
            lifecycleStage: project.lifecycleStage,
            safetyPosture: project.safetyPosture,
            directFileCount: project.directFileCount,
            directFolderCount: project.directFolderCount,
            markdownFiles: project.markdownFiles,
            pdfFiles: project.pdfFiles,
            gdocFiles: 1,
            csvFiles: project.csvFiles,
            xlsxFiles: project.xlsxFiles,
            documents: [localDraft, linkedGoogleDoc]
        )

        XCTAssertEqual(item.canonicalDraftDocument?.id, localDraft.id)
    }

    func testCanonicalDraftPrefersLocalAuthoredDraftWhenNoGoogleDraftPointerExists() {
        let project = makeProject(
            id: "local-draft",
            title: "Local Draft Project",
            projectType: .journalism,
            status: "active",
            safety: .internalOnly,
            deliverable: "Story",
            hasAgents: true,
            started: "2026-07-06"
        )
        let localDraft = WorkspaceDocument(
            id: "/tmp/local-draft/Draft.md",
            path: "/tmp/local-draft/Draft.md",
            title: "Working Draft",
            fileExtension: "md",
            provider: .localFile,
            role: .draft,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )
        let item = WorkspaceItem(
            id: project.id,
            section: project.section,
            path: project.path,
            readmePath: project.readmePath,
            agentsPath: project.agentsPath,
            title: project.title,
            summary: project.summary,
            agentsSummary: project.agentsSummary,
            frontmatter: project.frontmatter,
            googleDriveFolderURL: nil,
            projectType: project.projectType,
            lifecycleStage: project.lifecycleStage,
            safetyPosture: project.safetyPosture,
            directFileCount: project.directFileCount,
            directFolderCount: project.directFolderCount,
            markdownFiles: project.markdownFiles,
            pdfFiles: project.pdfFiles,
            gdocFiles: 0,
            csvFiles: project.csvFiles,
            xlsxFiles: project.xlsxFiles,
            documents: [localDraft]
        )

        XCTAssertEqual(item.canonicalDraftDocument?.id, localDraft.id)
        XCTAssertFalse(item.isLikelyDerivedSnapshot(localDraft))
    }

    func testProjectSummariesHideWorkflowAndSetupFlagsFromCards() throws {
        let project = makeProject(
            id: "review",
            title: "Review Project",
            projectType: .journalism,
            status: "active",
            safety: .unknown,
            deliverable: "",
            hasAgents: false,
            started: "2026-07-06"
        )
        let failedRun = WorkflowRun(
            id: "run-1",
            workflowID: "refresh-knowledge-ops",
            workflowLabel: "Refresh knowledge ops",
            startedAt: "2026-07-06T10-00-00Z",
            finishedAt: "2026-07-06T10-01-00Z",
            exitCode: 1,
            commandPreview: "cmd",
            workingDirectory: "/tmp",
            stdoutPath: "/tmp/stdout",
            stderrPath: "/tmp/stderr",
            manifestPath: "/tmp/manifest",
            artifactPaths: [],
            selectionPath: project.path
        )

        let summary = try XCTUnwrap(OverviewDeriver.projectSummaries(
            from: WorkspaceSnapshot(scannedAt: .now, items: [project], publication: .empty),
            runs: [failedRun]
        ).first)

        XCTAssertEqual(summary.flags, [
            "Workflow needs attention",
            "Project setup incomplete",
            "Needs review before sharing"
        ])
        XCTAssertEqual(summary.displayFlags, ["Needs review before sharing"])
    }

    private func makeProject(
        id: String,
        title: String,
        projectType: WorkspaceProjectType,
        status: String,
        safety: WorkspaceSafetyPosture,
        deliverable: String,
        hasAgents: Bool,
        started: String
    ) -> WorkspaceItem {
        let frontmatter = [
            "type": "project",
            "project": title,
            "status": status,
            "started": started,
            "owner": "Jan",
            "deliverable": deliverable
        ].filter { !$0.value.isEmpty }

        return WorkspaceItem(
            id: id,
            section: .projects,
            path: "/tmp/\(id)",
            readmePath: "/tmp/\(id)/README.md",
            agentsPath: hasAgents ? "/tmp/\(id)/AGENTS.md" : nil,
            title: title,
            summary: "Summary for \(title)",
            agentsSummary: hasAgents ? "Local rules" : "",
            frontmatter: frontmatter,
            googleDriveFolderURL: nil,
            projectType: projectType,
            lifecycleStage: status.capitalized,
            safetyPosture: safety,
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
