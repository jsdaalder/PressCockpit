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

    func testChoosingImmediateDocumentsAddsDedicatedWizardStep() {
        var draft = ScaffoldProjectWizardDraft()
        draft.hasPitch = false
        draft.summaryText = "A short project summary."
        draft.sourceMaterialChoice = .now

        let steps = scaffoldProjectWizardOrderedSteps(for: draft, currentStep: .priority)
        let expected: [ScaffoldProjectWizardStep] = [
            .workingTitle,
            .projectKind,
            .startingPoint,
            .summary,
            .sourceMaterial,
            .documentSelection,
            .priority,
            .review
        ]

        XCTAssertEqual(steps, expected)
    }

    func testDeferringDocumentsSkipsDedicatedWizardStep() {
        var draft = ScaffoldProjectWizardDraft()
        draft.hasPitch = false
        draft.summaryText = "A short project summary."
        draft.sourceMaterialChoice = .later

        let steps = scaffoldProjectWizardOrderedSteps(for: draft, currentStep: .priority)
        let expected: [ScaffoldProjectWizardStep] = [
            .workingTitle,
            .projectKind,
            .startingPoint,
            .summary,
            .sourceMaterial,
            .priority,
            .review
        ]

        XCTAssertEqual(steps, expected)
    }

    func testDraftWithoutAnswersIsNotDirty() {
        let draft = ScaffoldProjectWizardDraft()

        XCTAssertFalse(draft.hasUserInput)
    }

    func testDraftWithStagedDocumentsIsDirty() {
        var draft = ScaffoldProjectWizardDraft()
        draft.stagedDocumentDirectoryPath = "/tmp/staged"
        draft.stagedDocuments = [
            ScaffoldStagedDocument(
                sourcePath: "/tmp/source.pdf",
                stagedPath: "/tmp/staged/source.pdf",
                isDirectory: false
            )
        ]

        XCTAssertTrue(draft.hasUserInput)
    }

    func testDraftWithDossierLinkIsDirty() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierSlug = "voedselcrisis_2027"

        XCTAssertTrue(draft.hasUserInput)
    }

    func testEffectiveDossierChoiceDefaultsToNone() {
        let draft = ScaffoldProjectWizardDraft()

        XCTAssertEqual(draft.effectiveDossierChoice(availableDossierSlugs: []), .none)
    }

    func testEffectiveDossierChoiceInfersExistingDossierFromSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierSlug = "voedselcrisis_2027"

        XCTAssertEqual(
            draft.effectiveDossierChoice(availableDossierSlugs: ["voedselcrisis_2027"]),
            .existing
        )
    }

    func testEffectiveDossierChoiceInfersNewDossierFromCustomSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierSlug = "new_investigation_theme"

        XCTAssertEqual(
            draft.effectiveDossierChoice(availableDossierSlugs: ["voedselcrisis_2027"]),
            .new
        )
    }

    func testChoosingNewDossierClearsExistingSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierSlug = "voedselcrisis_2027"

        draft.updateDossierChoice(.new, availableDossierSlugs: ["voedselcrisis_2027"])

        XCTAssertEqual(draft.dossierChoice, .new)
        XCTAssertEqual(draft.dossierSlug, "")
    }

    func testChoosingExistingDossierPrefillsFirstAvailableSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierSlug = "new_investigation_theme"

        draft.updateDossierChoice(
            .existing,
            availableDossierSlugs: ["straat_van_hormuz", "voedselcrisis_2027"]
        )

        XCTAssertEqual(draft.dossierChoice, .existing)
        XCTAssertEqual(draft.dossierSlug, "straat_van_hormuz")
    }

    func testChoosingNoDossierClearsSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierSlug = "voedselcrisis_2027"

        draft.updateDossierChoice(.none, availableDossierSlugs: ["voedselcrisis_2027"])

        XCTAssertEqual(draft.dossierChoice, .none)
        XCTAssertEqual(draft.dossierSlug, "")
    }

    func testNoDossierSelectionIsAlwaysValid() {
        let draft = ScaffoldProjectWizardDraft()

        XCTAssertTrue(draft.hasValidDossierSelection(availableDossierSlugs: []))
    }

    func testNewDossierSelectionRequiresSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierChoice = .new

        XCTAssertFalse(draft.hasValidDossierSelection(availableDossierSlugs: []))

        draft.dossierSlug = "new_investigation_theme"

        XCTAssertTrue(draft.hasValidDossierSelection(availableDossierSlugs: []))
    }

    func testExistingDossierSelectionRequiresSlug() {
        var draft = ScaffoldProjectWizardDraft()
        draft.dossierChoice = .existing

        XCTAssertFalse(draft.hasValidDossierSelection(availableDossierSlugs: []))

        draft.dossierSlug = "voedselcrisis_2027"

        XCTAssertTrue(draft.hasValidDossierSelection(availableDossierSlugs: []))
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

        XCTAssertNil(state.textValues["status"])
        XCTAssertEqual(state.textValues["section_answer_1"], "")
        XCTAssertEqual(state.textValues["section_answer_2"], "")
        XCTAssertEqual(state.textValues["section_answer_3"], "")
        XCTAssertEqual(state.textValues["dossier"], "")
    }

    func testMappedStateIncludesStructuredAnswers() throws {
        var draft = ScaffoldProjectWizardDraft()
        draft.updateWorkingTitle("Climate Story", workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        draft.summaryText = "A short project summary."
        draft.wantsSummaryStructuring = true
        draft.dossierSlug = "voedselcrisis_2027"
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

        XCTAssertNil(state.textValues["status"])
        XCTAssertEqual(state.textValues["section_answer_1"], "Main reporting question")
        XCTAssertEqual(state.textValues["section_answer_2"], "Working hypothesis")
        XCTAssertEqual(state.textValues["section_answer_3"], "Why this matters now")
        XCTAssertEqual(state.textValues["dossier"], "voedselcrisis_2027")
    }

    func testMappedStateIncludesNewDossierSlugWithoutExistingFolder() throws {
        var draft = ScaffoldProjectWizardDraft()
        draft.updateWorkingTitle("Climate Story", workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"))
        draft.summaryText = "A short project summary."
        draft.dossierChoice = .new
        draft.dossierSlug = "new_investigation_theme"

        let workflow = WorkflowRegistry(
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            appProfile: .standard
        ).allWorkflows().first(where: { $0.id == "scaffold-project" })

        let state = draft.mappedState(
            for: try XCTUnwrap(workflow),
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace")
        )

        XCTAssertEqual(state.textValues["dossier"], "new_investigation_theme")
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
