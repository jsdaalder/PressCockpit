import XCTest
@testable import JournalismWorkflowHub

final class ProjectTrustRowsTests: XCTestCase {
    func testActiveProjectTrustRowsDoNotShowInactiveReason() {
        let item = makeProject(
            id: "active-project",
            title: "Active Project",
            frontmatter: [
                "activity_state": "active",
                "workflow_stage": "active_investigation"
            ]
        )

        XCTAssertEqual(value(for: "Activity state", in: item.projectTrustRows), "Active")
        XCTAssertEqual(value(for: "Workflow stage", in: item.projectTrustRows), "Investigation")
        XCTAssertNil(value(for: "Inactive reason", in: item.projectTrustRows))
        XCTAssertEqual(value(for: "State source", in: item.projectTrustRows), "Explicit frontmatter")
        XCTAssertEqual(value(for: "Dossier", in: item.projectTrustRows), "None linked yet")
        XCTAssertEqual(value(for: "Canonical draft", in: item.projectTrustRows), "Not decided yet")
        XCTAssertEqual(value(for: "Handling", in: item.projectTrustRows), "Needs review")
    }

    func testInactiveWaitingProjectTrustRowsShowInactiveReason() {
        let item = makeProject(
            id: "waiting-project",
            title: "Waiting Project",
            frontmatter: [
                "activity_state": "inactive",
                "workflow_stage": "feasibility_study",
                "inactive_reason": "waiting"
            ]
        )

        XCTAssertEqual(value(for: "Activity state", in: item.projectTrustRows), "Inactive")
        XCTAssertEqual(value(for: "Workflow stage", in: item.projectTrustRows), "Feasibility study")
        XCTAssertEqual(value(for: "Inactive reason", in: item.projectTrustRows), "Waiting")
        XCTAssertEqual(value(for: "State source", in: item.projectTrustRows), "Explicit frontmatter")
    }

    func testFinishedProjectTrustRowsRespectLegacyFallback() {
        let item = makeProject(
            id: "finished-project",
            title: "Finished Project",
            frontmatter: [
                "status": "done"
            ]
        )

        XCTAssertEqual(value(for: "Activity state", in: item.projectTrustRows), "Inactive")
        XCTAssertEqual(value(for: "Workflow stage", in: item.projectTrustRows), "Published")
        XCTAssertEqual(value(for: "Inactive reason", in: item.projectTrustRows), "Finished")
        XCTAssertEqual(value(for: "State source", in: item.projectTrustRows), "Compatibility fallback from `status`")
    }

    func testProjectTrustRowsShowLinkedDossier() {
        let item = makeProject(
            id: "dossier-project",
            title: "Dossier Project",
            frontmatter: [
                "activity_state": "active",
                "workflow_stage": "active_investigation",
                "dossier": "voedselcrisis_2027"
            ]
        )

        XCTAssertEqual(value(for: "Dossier", in: item.projectTrustRows), "voedselcrisis_2027")
    }

    func testProjectTrustRowsDescribeLocalCanonicalDraft() {
        let localDraft = WorkspaceDocument(
            id: "/tmp/local-draft/Draft.docx",
            path: "/tmp/local-draft/Draft.docx",
            title: "Draft",
            fileExtension: "docx",
            provider: .localFile,
            role: .draft,
            cacheState: .localFile,
            externalURL: nil,
            docID: nil,
            cachePath: nil,
            cachedOn: nil
        )

        let item = makeProject(
            id: "local-draft",
            title: "Local Draft",
            frontmatter: [
                "activity_state": "active",
                "workflow_stage": "active_investigation"
            ],
            documents: [localDraft]
        )

        XCTAssertEqual(value(for: "Canonical draft", in: item.projectTrustRows), "Draft")
        XCTAssertEqual(value(for: "Draft target", in: item.projectTrustRows), "Local file • Draft • current canonical draft target")
    }

    func testProjectTrustRowsDescribePromotedGoogleDraft() {
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

        let item = makeProject(
            id: "promoted-google-draft",
            title: "Promoted Google Draft",
            frontmatter: [
                "activity_state": "active",
                "workflow_stage": "active_investigation"
            ],
            documents: [localDraft, promotedGoogleDraft]
        )

        XCTAssertEqual(value(for: "Canonical draft", in: item.projectTrustRows), "Draft")
        XCTAssertEqual(value(for: "Draft target", in: item.projectTrustRows), "Google Doc • Draft • current canonical draft target")
    }

    private func value(for label: String, in rows: [(String, String)]) -> String? {
        rows.first(where: { $0.0 == label })?.1
    }

    private func makeProject(
        id: String,
        title: String,
        frontmatter: [String: String],
        documents: [WorkspaceDocument] = []
    ) -> WorkspaceItem {
        let mergedFrontmatter = [
            "type": "project",
            "project": title,
            "status": "active",
            "started": "2026-07-14",
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
            directFileCount: documents.count,
            directFolderCount: 1,
            markdownFiles: documents.filter { $0.fileExtension == "md" }.count,
            pdfFiles: documents.filter { $0.fileExtension == "pdf" }.count,
            gdocFiles: documents.filter { $0.fileExtension == "gdoc" }.count,
            csvFiles: 0,
            xlsxFiles: 0,
            documents: documents
        )
    }
}
