import XCTest
@testable import JournalismWorkflowHub

final class ScaffoldProjectWizardDraftTests: XCTestCase {
    func testSyncAdvancedDefaultsDoesNotPreseedPlaceholderPathBeforeTitleExists() {
        var draft = ScaffoldProjectWizardDraft()
        let workspaceRoot = URL(fileURLWithPath: "/tmp/workspace")

        draft.syncAdvancedDefaults(workspaceRoot: workspaceRoot)

        XCTAssertEqual(draft.folderNameOverride, "")
        XCTAssertEqual(draft.projectRootOverride, "")
    }

    func testUpdatingWorkingTitleRefreshesDerivedFolderAndProjectRoot() {
        var draft = ScaffoldProjectWizardDraft()
        let workspaceRoot = URL(fileURLWithPath: "/tmp/workspace")

        draft.updateWorkingTitle("Climate Story", workspaceRoot: workspaceRoot)

        XCTAssertEqual(draft.workingTitle, "Climate Story")
        XCTAssertEqual(draft.folderNameOverride, "climate_story")
        XCTAssertEqual(
            draft.projectRootOverride,
            workspaceRoot
                .appendingPathComponent("Projects", isDirectory: true)
                .appendingPathComponent(currentYearString(), isDirectory: true)
                .appendingPathComponent("climate_story", isDirectory: true)
                .path
        )
    }

    func testPunctuationOnlyTitleDoesNotFallbackToNewProject() {
        var draft = ScaffoldProjectWizardDraft()
        let workspaceRoot = URL(fileURLWithPath: "/tmp/workspace")

        draft.updateWorkingTitle("!!!", workspaceRoot: workspaceRoot)

        XCTAssertEqual(draft.workingTitle, "!!!")
        XCTAssertEqual(draft.folderNameOverride, "")
        XCTAssertEqual(draft.derivedFolderName, "")
        XCTAssertEqual(draft.projectRootOverride, "")
        XCTAssertEqual(draft.derivedProjectRoot(workspaceRoot: workspaceRoot), "")
        XCTAssertFalse(draft.hasUsableDerivedFolderName)
    }

    func testSummaryOnlyDraftCanSkipStructureStepByDefault() {
        var draft = ScaffoldProjectWizardDraft()
        draft.hasPitch = false
        draft.summaryText = "A short project summary."

        XCTAssertTrue(draft.requiresSummaryStructuring)
        XCTAssertFalse(draft.wantsSummaryStructuring)
        XCTAssertFalse(draft.shouldShowSummaryStructuringStep)
        XCTAssertFalse(draft.hasCompletedSummaryStructuring)
    }

    func testSummaryOnlyDraftCanOptIntoExplicitStructureStep() {
        var draft = ScaffoldProjectWizardDraft()
        draft.hasPitch = false
        draft.summaryText = "A short project summary."
        draft.wantsSummaryStructuring = true

        XCTAssertTrue(draft.shouldShowSummaryStructuringStep)

        draft.structureAnswerOne = "Main question"
        draft.structureAnswerTwo = "Working hypothesis"
        draft.structureAnswerThree = "Why now"

        XCTAssertTrue(draft.hasCompletedSummaryStructuring)
    }

    func testMappedStateLeavesStructuredAnswersEmptyWhenStepIsSkipped() throws {
        var draft = ScaffoldProjectWizardDraft()
        draft.updateWorkingTitle("Climate Story", workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        draft.summaryText = "A short project summary."

        let workflow = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standard
        ).allWorkflows().first(where: { $0.id == "scaffold-project" })

        let state = draft.mappedState(
            for: try XCTUnwrap(workflow),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
        )

        XCTAssertEqual(state.textValues["section_answer_1"], "")
        XCTAssertEqual(state.textValues["section_answer_2"], "")
        XCTAssertEqual(state.textValues["section_answer_3"], "")
    }

    func testMappedStateIncludesStructuredAnswers() throws {
        var draft = ScaffoldProjectWizardDraft()
        draft.updateWorkingTitle("Climate Story", workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        draft.summaryText = "A short project summary."
        draft.wantsSummaryStructuring = true
        draft.structureAnswerOne = "Main reporting question"
        draft.structureAnswerTwo = "Working hypothesis"
        draft.structureAnswerThree = "Why this matters now"

        let workflow = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standard
        ).allWorkflows().first(where: { $0.id == "scaffold-project" })

        let state = draft.mappedState(
            for: try XCTUnwrap(workflow),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
        )

        XCTAssertEqual(state.textValues["section_answer_1"], "Main reporting question")
        XCTAssertEqual(state.textValues["section_answer_2"], "Working hypothesis")
        XCTAssertEqual(state.textValues["section_answer_3"], "Why this matters now")
    }

    private func currentYearString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy"
        return formatter.string(from: .now)
    }
}
