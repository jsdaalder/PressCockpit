import AppKit
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

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

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

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

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

    func testReopeningProjectReloadsExternalReadmeRepairs() throws {
        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = workspaceRoot.appendingPathComponent("Projects/2026/demo_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        # Demo Story

        A project before metadata repair.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let projectID = try XCTUnwrap(store.snapshot.items.first?.id)
        store.select(.workspace(projectID))
        XCTAssertTrue(store.selectedWorkspaceItem?.frontmatter.isEmpty ?? false)
        XCTAssertNil(store.selectedWorkspaceItem?.activityState)
        XCTAssertNil(store.selectedWorkspaceItem?.workflowStage)

        try """
        ---
        type: project
        project: Demo Story
        activity_state: active
        workflow_stage: active_investigation
        project_type: journalism
        safety: unknown
        ---

        # Demo Story

        A project after metadata repair.
        """.write(to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        store.select(.overview)
        store.select(.workspace(projectID))

        let refreshedItem = try XCTUnwrap(store.selectedWorkspaceItem)
        XCTAssertEqual(refreshedItem.activityState, .active)
        XCTAssertEqual(refreshedItem.workflowStage, .activeInvestigation)
        XCTAssertEqual(refreshedItem.projectType, .journalism)
        XCTAssertEqual(refreshedItem.safetyPosture, .unknown)
        XCTAssertEqual(refreshedItem.frontmatter["project_type"], "journalism")
    }

    func testCaptureSelectionParticipatesInNavigationHistory() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        )

        store.select(.capture)
        store.select(.publication)

        XCTAssertEqual(store.selection, .publication)
        XCTAssertTrue(store.canNavigateBack)

        store.goBack()
        XCTAssertEqual(store.selection, .capture)

        store.goBack()
        XCTAssertEqual(store.selection, .overview)
    }

    func testAppStoreInitializesEmptyCaptureShell() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        XCTAssertTrue(store.captureRecords.isEmpty)
        XCTAssertTrue(captureStore.loadRecords()?.isEmpty ?? true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: captureStore.storageDirectory.path))
    }

    func testAppStoreRecoversCaptureItemsAfterWorkspaceRootMismatch() throws {
        let originalWorkspaceRoot = try makeWorkspaceRoot()
        let replacementWorkspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let originalStore = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: originalWorkspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: CaptureStore(workspaceRoot: originalWorkspaceRoot, supportDirectory: supportRoot)
        )

        waitForCaptureAsyncWork {
            await originalStore.saveQuickCaptureNote("Recover this after a workspace switch.")
        }

        let replacementCaptureStore = CaptureStore(workspaceRoot: replacementWorkspaceRoot, supportDirectory: supportRoot)
        let catalogURL = replacementCaptureStore.storageDirectory.appendingPathComponent("capture_catalog.json")
        let catalogDataBeforeLaunch = try Data(contentsOf: catalogURL)
        let recoveredStore = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: replacementWorkspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: replacementCaptureStore
        )

        let recoveredRecord = try XCTUnwrap(recoveredStore.captureRecords.first)
        XCTAssertEqual(recoveredStore.captureRecords.count, 1)
        XCTAssertEqual(recoveredRecord.state, .needsReview)
        XCTAssertNotNil(recoveredRecord.importedStoragePath)
        XCTAssertEqual(catalogDataBeforeLaunch, try Data(contentsOf: catalogURL))
        guard case .workspaceMismatch = replacementCaptureStore.loadCatalog() else {
            return XCTFail("Expected launch recovery to preserve the mismatched catalog file.")
        }
    }

    func testAppStoreRecoversCaptureItemsWhenCatalogWasClearedButPayloadsRemain() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)

        let originalStore = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await originalStore.saveQuickCaptureNote("Recover this after metadata loss.")
        }

        let storedItemPath = try XCTUnwrap(originalStore.captureRecords.first?.importedStoragePath)
        captureStore.replace(with: [])

        let recoveredStore = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let recoveredRecord = try XCTUnwrap(recoveredStore.captureRecords.first)
        XCTAssertEqual(recoveredStore.captureRecords.count, 1)
        XCTAssertEqual(recoveredRecord.state, .needsReview)
        let recoveredPath = try XCTUnwrap(recoveredRecord.importedStoragePath)
        XCTAssertEqual(normalizedPath(recoveredPath), normalizedPath(storedItemPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveredPath))
        XCTAssertEqual(captureStore.loadRecords()?.count, 1)
    }

    func testReusingExistingScaffoldProjectRoutesIntoPostCreateState() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

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

    func testReusingExistingScaffoldProjectWithoutImmediateDocumentsKeepsPromptDisabled() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .later
        )

        let postCreateState = try XCTUnwrap(store.scaffoldPostCreateState)
        XCTAssertEqual(postCreateState.mode, .reused)
        XCTAssertFalse(postCreateState.shouldAutoPromptForDocuments)
        XCTAssertEqual(store.statusMessage, "Using existing project")
    }

    func testReusingExistingScaffoldProjectImportsStagedDocumentsImmediately() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        let stagingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)

        let sourceURL = workspaceRoot.appendingPathComponent("external_note.md")
        try "External note".write(to: sourceURL, atomically: true, encoding: .utf8)

        let stagedURL = stagingRoot.appendingPathComponent("external_note.md")
        try "External note".write(to: stagedURL, atomically: true, encoding: .utf8)

        store.scaffoldProjectWizardDraft.stagedDocumentDirectoryPath = stagingRoot.path
        store.scaffoldProjectWizardDraft.stagedDocuments = [
            ScaffoldStagedDocument(
                sourcePath: sourceURL.path,
                stagedPath: stagedURL.path,
                isDirectory: false
            )
        ]

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .now
        )

        let postCreateState = try XCTUnwrap(store.scaffoldPostCreateState)
        XCTAssertEqual(postCreateState.importedItemCount, 1)
        XCTAssertFalse(postCreateState.shouldAutoPromptForDocuments)
        XCTAssertEqual(store.statusMessage, "Using existing project. Imported staged documents.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: postCreateState.importedPaths[0]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))
    }

    func testCancelingScaffoldWizardClearsDraftAndReturnsToPreviousSelection() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let stagingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: nil)
        let stagedURL = stagingRoot.appendingPathComponent("research.pdf")
        try Data("draft".utf8).write(to: stagedURL)

        store.select(.workflow("scaffold-project"))
        store.scaffoldProjectWizardStep = .documentSelection
        store.scaffoldProjectWizardDraft.workingTitle = "Draft title"
        store.scaffoldProjectWizardDraft.stagedDocumentDirectoryPath = stagingRoot.path
        store.scaffoldProjectWizardDraft.stagedDocuments = [
            ScaffoldStagedDocument(
                sourcePath: "/tmp/research.pdf",
                stagedPath: stagedURL.path,
                isDirectory: false
            )
        ]

        store.cancelScaffoldProjectWizard()

        XCTAssertEqual(store.selection, .overview)
        XCTAssertEqual(store.scaffoldProjectWizardStep, .workingTitle)
        XCTAssertEqual(store.scaffoldProjectWizardDraft, ScaffoldProjectWizardDraft())
        XCTAssertEqual(store.statusMessage, "Canceled new project setup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingRoot.path))
    }

    func testScaffoldPostCreateStateTracksImmediateDocumentStepUntilImportStarts() {
        var state = ScaffoldPostCreateState(
            id: "demo",
            mode: .created,
            projectTitle: "Demo Story",
            projectRoot: "/tmp/demo_story",
            readmePath: "/tmp/demo_story/README.md",
            sourceMaterialChoice: .now,
            shouldAutoPromptForDocuments: true,
            importedPaths: []
        )

        XCTAssertTrue(state.isAwaitingImmediateDocumentImport)

        state.importedPaths = ["/tmp/demo_story/docs/research.pdf"]

        XCTAssertFalse(state.isAwaitingImmediateDocumentImport)
    }

    func testCompleteScaffoldPostCreateDismissesSheetAndPublishesSuccessFeedback() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .later
        )

        let sourceFile = workspaceRoot.appendingPathComponent("source_note.md")
        try """
        Lead finding from the imported note.

        Supporting detail that should appear in the synthesized overview.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)
        var state = try XCTUnwrap(store.scaffoldPostCreateState)
        state.importedPaths = importedPaths
        store.scaffoldPostCreateState = state

        await store.completeScaffoldPostCreate()

        let feedback = try XCTUnwrap(store.projectDocumentImportFeedback(for: project))
        let overviewPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs/docs_overview.md")
        let overviewText = try String(contentsOf: overviewPath, encoding: .utf8)

        XCTAssertNil(store.scaffoldPostCreateState)
        XCTAssertFalse(store.isFinishingScaffoldPostCreate)
        XCTAssertEqual(store.statusMessage, "Attached 1 item to Demo Story and updated docs overview")
        XCTAssertEqual(feedback.title, "Docs attached")
        XCTAssertEqual(feedback.style, .success)
        XCTAssertTrue(feedback.showsOpenDocsOverviewAction)
        XCTAssertTrue(overviewText.contains("Working summary from source_note.md"))
    }

    func testCompleteScaffoldPostCreateKeepsSheetOpenAndPublishesWarningFeedbackOnFailure() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .later
        )

        let sourceFile = workspaceRoot.appendingPathComponent("source_note.md")
        try """
        Lead finding from the imported note.

        Supporting detail that should stay reachable after a summary failure.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)
        let blockedOverviewURL = URL(fileURLWithPath: project.path).appendingPathComponent("docs/docs_overview.md", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedOverviewURL, withIntermediateDirectories: true, attributes: nil)

        var state = try XCTUnwrap(store.scaffoldPostCreateState)
        state.importedPaths = importedPaths
        store.scaffoldPostCreateState = state

        await store.completeScaffoldPostCreate()

        let feedback = try XCTUnwrap(store.projectDocumentImportFeedback(for: project))
        let alert = try XCTUnwrap(store.activeAlert)
        let preservedState = try XCTUnwrap(store.scaffoldPostCreateState)

        XCTAssertEqual(preservedState.importedPaths, importedPaths)
        XCTAssertFalse(store.isFinishingScaffoldPostCreate)
        XCTAssertEqual(store.statusMessage, "Attached 1 item to Demo Story, but docs overview update failed")
        XCTAssertEqual(feedback.title, "Docs attached, summary needs review")
        XCTAssertEqual(feedback.style, .warning)
        XCTAssertTrue(feedback.showsOpenDocsOverviewAction)
        XCTAssertEqual(alert.title, "Could not summarize docs overview")
    }

    func testCreateScaffoldDraftBuildsLocalDocxWithoutExternalTemplate() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        let expectedDraftURL = URL(fileURLWithPath: project.path)
            .appendingPathComponent(DraftSupport.localDraftFilename(projectTitle: project.title))

        store.reuseExistingScaffoldProject(
            projectTitle: project.title,
            projectRoot: project.path,
            sourceMaterialChoice: .later
        )
        store.createScaffoldDraft()

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDraftURL.path))
        XCTAssertEqual(store.statusMessage, "Created draft \(expectedDraftURL.lastPathComponent)")
        XCTAssertEqual(store.selection, .workspace(project.id))
        XCTAssertEqual(store.scaffoldPostCreateDraftDocument()?.url.standardizedFileURL, expectedDraftURL.standardizedFileURL)

        let document = try NSAttributedString(
            url: expectedDraftURL,
            options: [:],
            documentAttributes: nil
        )
        let text = document.string

        XCTAssertTrue(text.contains("Demo Story"))
        XCTAssertTrue(text.contains("[Nieuwsbrief]"))
        XCTAssertTrue(text.contains("[Speedread]"))
        XCTAssertTrue(text.contains("[Gerelateerde artikelen]"))
    }

    func testCreateProjectDraftWritesExplicitCanonicalDraftSelection() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        var revealedURLs: [[URL]] = []
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ), revealInFinder: { urls in
            revealedURLs.append(urls)
        })

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        let expectedDraftURL = URL(fileURLWithPath: project.path)
            .appendingPathComponent(DraftSupport.localDraftFilename(projectTitle: project.title))

        store.createProjectDraft(for: project)

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDraftURL.path))
        XCTAssertEqual(store.statusMessage, "Created draft \(expectedDraftURL.lastPathComponent)")

        let readmeText = try String(
            contentsOf: URL(fileURLWithPath: project.path).appendingPathComponent("README.md"),
            encoding: .utf8
        )
        XCTAssertTrue(readmeText.contains("canonical_draft: \(expectedDraftURL.lastPathComponent)"))

        let refreshedProject = try XCTUnwrap(store.snapshot.items.first(where: { $0.id == project.id }))
        XCTAssertEqual(refreshedProject.canonicalDraftDocument?.url.standardizedFileURL, expectedDraftURL.standardizedFileURL)
        XCTAssertTrue(revealedURLs.isEmpty)
    }

    func testCreateProjectPitchWritesExplicitCanonicalPitchSelection() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        var revealedURLs: [[URL]] = []
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ), revealInFinder: { urls in
            revealedURLs.append(urls)
        })

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        let expectedPitchURL = URL(fileURLWithPath: project.path).appendingPathComponent("Pitch.md")

        store.createProjectPitch(for: project)

        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPitchURL.path))
        XCTAssertEqual(store.statusMessage, "Created pitch Pitch.md")

        let readmeText = try String(
            contentsOf: URL(fileURLWithPath: project.path).appendingPathComponent("README.md"),
            encoding: .utf8
        )
        XCTAssertTrue(readmeText.contains("canonical_pitch: Pitch.md"))

        let pitchBody = try String(contentsOf: expectedPitchURL, encoding: .utf8)
        XCTAssertTrue(pitchBody.contains("## Core angle"))
        XCTAssertTrue(pitchBody.contains("## Questions for the editor"))

        let refreshedProject = try XCTUnwrap(store.snapshot.items.first(where: { $0.id == project.id }))
        XCTAssertEqual(refreshedProject.pitchDocument?.url.standardizedFileURL, expectedPitchURL.standardizedFileURL)
        XCTAssertTrue(revealedURLs.isEmpty)
    }

    func testCompleteOnboardingStartNewProjectSelectsScaffoldWorkflow() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .createWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.createBaseStructure = true
        draft.confirmedSeparateWorkspaceCreation = true
        draft.firstAction = .startNewProject

        try store.completeOnboarding(using: draft)

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.selection, .workflow("scaffold-project"))
        XCTAssertEqual(store.statusMessage, "Workspace ready")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceRoot.appendingPathComponent("Projects").path))
    }

    func testAppStoreStartsWithDiagnosticsLoggingEnabledByDefault() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            defaults: defaults,
            supportDirectory: supportRoot
        )

        XCTAssertTrue(store.isDiagnosticsLoggingEnabled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalismWorkflowHubLogFileURL(supportDirectory: supportRoot).path))
    }

    func testCompleteOnboardingPersistsDiagnosticsLoggingChoice() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standard,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            defaults: defaults,
            supportDirectory: supportRoot
        )

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .existingWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.diagnosticsLoggingEnabled = true
        draft.firstAction = .openOverview

        try store.completeOnboarding(using: draft)

        XCTAssertTrue(store.isDiagnosticsLoggingEnabled)
        XCTAssertTrue(OnboardingPreferences.diagnosticsLoggingEnabled(defaults: defaults))

        let logContents = try String(
            contentsOf: journalismWorkflowHubLogFileURL(supportDirectory: supportRoot),
            encoding: .utf8
        )
        XCTAssertTrue(logContents.contains("onboarding-complete"))
    }

    func testDisablingDiagnosticsLoggingStopsFurtherWritesAndAvoidsAbsolutePaths() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            defaults: defaults,
            supportDirectory: supportRoot
        )
        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

        XCTAssertTrue(store.isDiagnosticsLoggingEnabled)
        store.select(.workspace(project.id))

        let logURL = journalismWorkflowHubLogFileURL(supportDirectory: supportRoot)
        let enabledContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(enabledContents.contains("workspace-detail"))
        XCTAssertFalse(enabledContents.contains(workspaceRoot.path))

        store.setDiagnosticsLoggingEnabled(false)
        store.select(.overview)
        store.select(.workspace(project.id))

        let disabledContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(disabledContents, enabledContents)
        XCTAssertFalse(OnboardingPreferences.diagnosticsLoggingEnabled(defaults: defaults))
    }

    func testAppStoreStartsFollowingSystemAppearanceByDefault() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            defaults: defaults
        )

        XCTAssertEqual(store.appAppearancePreference, .system)
        XCTAssertNil(store.preferredColorScheme)
    }

    func testSettingDarkModePersistsAppearancePreference() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            defaults: defaults
        )

        store.setDarkModeEnabled(true)
        XCTAssertEqual(store.appAppearancePreference, .dark)
        XCTAssertEqual(store.preferredColorScheme, .dark)
        XCTAssertEqual(OnboardingPreferences.appAppearancePreference(defaults: defaults), .dark)

        store.setDarkModeEnabled(false)
        XCTAssertEqual(store.appAppearancePreference, .light)
        XCTAssertEqual(store.preferredColorScheme, .light)
        XCTAssertEqual(OnboardingPreferences.appAppearancePreference(defaults: defaults), .light)

        store.followSystemAppearance()
        XCTAssertEqual(store.appAppearancePreference, .system)
        XCTAssertNil(store.preferredColorScheme)
        XCTAssertEqual(OnboardingPreferences.appAppearancePreference(defaults: defaults), .system)
    }

    func testReopenOnboardingResetsCompletionState() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .existingWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.firstAction = .openOverview

        try store.completeOnboarding(using: draft)
        XCTAssertTrue(store.hasCompletedOnboarding)

        store.reopenOnboarding()

        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertEqual(store.onboardingLaunchMode, .firstRun)
        XCTAssertTrue(store.shouldShowOnboarding)
    }

    func testBeginWorkspaceSwitchPreservesCompletionStateAndShowsOnboarding() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .existingWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.firstAction = .openOverview

        try store.completeOnboarding(using: draft)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertFalse(store.shouldShowOnboarding)

        store.beginWorkspaceSwitch()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.onboardingLaunchMode, .switchWorkspace)
        XCTAssertTrue(store.shouldShowOnboarding)
    }

    func testCompletingWorkspaceSwitchUpdatesWorkspaceWithoutResettingOnboardingCompletion() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let originalRoot = try makeWorkspaceRoot()
        let replacementRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: originalRoot,
            demoWorkspaceRoot: nil
        ))

        var initialDraft = OnboardingDraft.initial(defaultNewWorkspacePath: originalRoot.path)
        initialDraft.startMode = .existingWorkspace
        initialDraft.workspacePath = originalRoot.path
        initialDraft.firstAction = .openOverview
        try store.completeOnboarding(using: initialDraft)

        store.beginWorkspaceSwitch()

        var switchDraft = OnboardingDraft.initial(defaultNewWorkspacePath: replacementRoot.path)
        switchDraft.startMode = .existingWorkspace
        switchDraft.workspacePath = replacementRoot.path
        switchDraft.firstAction = .openOverview

        try store.completeOnboarding(using: switchDraft)

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertFalse(store.shouldShowOnboarding)
        XCTAssertNil(store.onboardingLaunchMode)
        XCTAssertEqual(store.workspaceRoot.standardizedFileURL, replacementRoot.standardizedFileURL)
        XCTAssertEqual(store.selection, .overview)
    }

    func testCancelOnboardingLaunchDismissesWorkspaceSwitchAndPreservesCompletion() throws {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        var draft = OnboardingDraft.initial(defaultNewWorkspacePath: workspaceRoot.path)
        draft.startMode = .existingWorkspace
        draft.workspacePath = workspaceRoot.path
        draft.firstAction = .openOverview
        try store.completeOnboarding(using: draft)

        store.beginWorkspaceSwitch()
        store.cancelOnboardingLaunch()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertFalse(store.shouldShowOnboarding)
        XCTAssertNil(store.onboardingLaunchMode)
    }

    func testImportCaptureItemsCopiesFilesAndMarksThemForReview() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let firstFile = incomingRoot.appendingPathComponent("source_story.pdf")
        let secondFile = incomingRoot.appendingPathComponent("interview_notes.md")
        try Data("pdf".utf8).write(to: firstFile)
        try Data("# Notes".utf8).write(to: secondFile)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [firstFile, secondFile])
        }

        XCTAssertEqual(store.captureRecords.count, 2)
        XCTAssertTrue(store.captureRecords.allSatisfy { $0.state == .needsReview })
        XCTAssertEqual(Set(store.captureRecords.compactMap(\.originalSourcePath)), Set([firstFile.path, secondFile.path]))

        for record in store.captureRecords {
            let importedPath = try XCTUnwrap(record.importedStoragePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: importedPath))
        }

        let persisted = try XCTUnwrap(captureStore.loadRecords())
        XCTAssertEqual(persisted.count, 2)
        XCTAssertTrue(persisted.allSatisfy { $0.state == .needsReview })
    }

    func testImportCaptureFolderPreservesFolderTypeAndCopiesDirectory() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderURL = incomingRoot.appendingPathComponent("bauer_interview")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        try "Transcript".write(to: folderURL.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [folderURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(record.captureType, .folder)
        XCTAssertEqual(record.state, .needsReview)

        let importedPath = try XCTUnwrap(record.importedStoragePath)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: importedPath).appendingPathComponent("transcript.txt").path))
    }

    func testSaveQuickCaptureNoteCreatesMarkdownRecord() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("Check whether this source has KNMI data access.")
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(record.captureType, .note)
        XCTAssertEqual(record.state, .needsReview)
        XCTAssertEqual(record.displayName, "Check whether this source has KNMI data access.")

        let notePath = try XCTUnwrap(record.importedStoragePath)
        XCTAssertTrue(notePath.hasSuffix(".md"))
        let noteContents = try String(contentsOfFile: notePath)
        XCTAssertEqual(noteContents, "Check whether this source has KNMI data access.")
    }

    func testFailedCaptureImportRemainsVisibleInQueue() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let missingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.pdf")

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [missingFile])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(record.state, .failed)
        XCTAssertNil(record.importedStoragePath)
        XCTAssertNotNil(record.failureDescription)
    }

    func testCaptureTriageRecordsExcludeFailedImports() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let validFile = incomingRoot.appendingPathComponent("source_story.pdf")
        try Data("pdf".utf8).write(to: validFile)

        let missingFile = incomingRoot.appendingPathComponent("missing.pdf")

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [validFile, missingFile])
        }

        XCTAssertEqual(store.captureQueueRecords.count, 2)
        XCTAssertEqual(store.captureTriageRecords.count, 1)
        XCTAssertEqual(store.captureFailedRecords.count, 1)
        XCTAssertEqual(store.captureTriageRecords.first?.state, .needsReview)
        XCTAssertEqual(store.captureFailedRecords.first?.state, .failed)
    }

    func testSetCaptureUserNotePersistsOnRecord() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("A short note")
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        store.setCaptureUserNote("Important context for filing", for: record.id)

        let updated = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(updated.userNote, "Important context for filing")
        XCTAssertEqual(captureStore.loadRecords()?.first?.userNote, "Important context for filing")
    }

    func testAssignCaptureRecordCopiesFileIntoProjectDocsAndMarksAssigned() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let fileURL = incomingRoot.appendingPathComponent("source_story.pdf")
        try Data("pdf".utf8).write(to: fileURL)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [fileURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let project = try XCTUnwrap(store.captureAssignmentTargets.first(where: { $0.section == .projects }))

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(record.id, to: project, note: "Useful for the main story.")
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(assigned.state, .assigned)
        XCTAssertEqual(assigned.userNote, "Useful for the main story.")
        XCTAssertEqual(assigned.assignedTargetPath, project.path)
        let destinationPath = try XCTUnwrap(assigned.assignedDestinationPath)
        let factsPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs/facts.md")
        let facts = try String(contentsOf: factsPath, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(destinationPath.contains("/docs/"))
        XCTAssertTrue(facts.contains("# Facts"))
        XCTAssertTrue(facts.contains("Fact: Useful for the main story."))
        XCTAssertTrue(facts.contains("Source: source_story.pdf"))
        XCTAssertEqual(store.captureQueueRecords.count, 0)
        XCTAssertEqual(store.captureAssignedRecords.count, 1)
        XCTAssertEqual(store.statusMessage, "Assigned source_story.pdf to Demo Story and saved note to facts")
    }

    func testAssignCaptureRecordAppendsFactsWithoutOverwritingExistingEntries() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let firstFileURL = incomingRoot.appendingPathComponent("source_story.pdf")
        let secondFileURL = incomingRoot.appendingPathComponent("market_note.pdf")
        try Data("pdf".utf8).write(to: firstFileURL)
        try Data("pdf".utf8).write(to: secondFileURL)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [firstFileURL, secondFileURL])
        }

        let project = try XCTUnwrap(store.captureAssignmentTargets.first(where: { $0.section == .projects }))
        let firstRecord = try XCTUnwrap(store.captureRecords.first(where: { $0.displayTitle == "source_story.pdf" }))
        let secondRecord = try XCTUnwrap(store.captureRecords.first(where: { $0.displayTitle == "market_note.pdf" }))

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(firstRecord.id, to: project, note: "India accounts for 8.9% of EU steel imports.")
        }

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(secondRecord.id, to: project, note: "This makes India a major importer, even if it is not the biggest.")
        }

        let factsPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs/facts.md")
        let facts = try String(contentsOf: factsPath, encoding: .utf8)

        XCTAssertEqual(facts.components(separatedBy: "# Facts").count - 1, 1)
        XCTAssertTrue(facts.contains("Fact: India accounts for 8.9% of EU steel imports."))
        XCTAssertTrue(facts.contains("Fact: This makes India a major importer, even if it is not the biggest."))
        XCTAssertTrue(facts.contains("Source: source_story.pdf"))
        XCTAssertTrue(facts.contains("Source: market_note.pdf"))
    }

    func testAssignCaptureRecordCopiesFolderIntoProjectDocs() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderURL = incomingRoot.appendingPathComponent("bauer_interview")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        try "Transcript".write(to: folderURL.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [folderURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let project = try XCTUnwrap(store.captureAssignmentTargets.first(where: { $0.section == .projects }))

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(record.id, to: project, note: "")
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(assigned.state, .assigned)
        let destinationPath = try XCTUnwrap(assigned.assignedDestinationPath)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: destinationPath).appendingPathComponent("transcript.txt").path))
    }

    func testAssignCaptureRecordFailureKeepsItemInTriage() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let fileURL = incomingRoot.appendingPathComponent("source_story.pdf")
        try Data("pdf".utf8).write(to: fileURL)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [fileURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let project = try XCTUnwrap(store.captureAssignmentTargets.first(where: { $0.section == .projects }))
        let docsPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs").path
        try "block docs folder creation".write(toFile: docsPath, atomically: true, encoding: .utf8)

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(record.id, to: project, note: "Useful for the main story.")
        }

        let failedAssignment = try XCTUnwrap(store.captureRecords.first)
        let alert = try XCTUnwrap(store.activeAlert)

        XCTAssertEqual(failedAssignment.state, .needsReview)
        XCTAssertEqual(failedAssignment.userNote, "Useful for the main story.")
        XCTAssertNotNil(failedAssignment.failureDescription)
        XCTAssertEqual(store.captureTriageRecords.count, 1)
        XCTAssertEqual(store.captureFailedRecords.count, 0)
        XCTAssertEqual(alert.title, "Could not assign capture item")
        XCTAssertEqual(store.statusMessage, "Could not assign source_story.pdf")
    }

    func testCreatePlaceholderProjectFromCaptureRecordScaffoldsProjectAndAssignsStoredCopy() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("Inspectors ignored repeated warning signs")
        }

        let record = try XCTUnwrap(store.captureRecords.first)

        waitForCaptureAsyncWork {
            _ = await store.createPlaceholderProjectFromCaptureRecord(
                record.id,
                note: "Placeholder lead from Capture. Confirm the reporting angle later."
            )
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(assigned.state, .assigned)
        XCTAssertEqual(assigned.userNote, "Placeholder lead from Capture. Confirm the reporting angle later.")

        let projectPath = try XCTUnwrap(assigned.assignedTargetPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: projectPath).appendingPathComponent("README.md").path))

        let readme = try String(
            contentsOf: URL(fileURLWithPath: projectPath).appendingPathComponent("README.md"),
            encoding: .utf8
        )
        let facts = try String(
            contentsOf: URL(fileURLWithPath: projectPath).appendingPathComponent("docs/facts.md"),
            encoding: .utf8
        )
        XCTAssertTrue(readme.contains("project: Inspectors ignored repeated warning signs"))
        XCTAssertTrue(readme.contains("deliverable: Placeholder lead from Capture. Confirm the reporting angle later."))
        XCTAssertTrue(facts.contains("Fact: Placeholder lead from Capture. Confirm the reporting angle later."))
        XCTAssertTrue(facts.contains("Source: inspectors_ignored_repeated_warning_signs_"))
        XCTAssertEqual(store.statusMessage, "Created placeholder project Inspectors ignored repeated warning signs and saved note to facts")

        let destinationPath = try XCTUnwrap(assigned.assignedDestinationPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(destinationPath.contains("/docs/"))
        let standardizedProjectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        XCTAssertTrue(
            store.captureAssignmentTargets.contains { target in
                URL(fileURLWithPath: target.path).standardizedFileURL.path == standardizedProjectPath
            }
        )
    }

    func testCreatePlaceholderProjectFromCaptureRecordUsesUniqueProjectFolderWhenTitleAlreadyExists() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("Demo Story")
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let existingProject = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))

        waitForCaptureAsyncWork {
            _ = await store.createPlaceholderProjectFromCaptureRecord(record.id, note: "")
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        let projectPath = try XCTUnwrap(assigned.assignedTargetPath)
        XCTAssertNotEqual(projectPath, existingProject.path)
        XCTAssertTrue(projectPath.hasSuffix("/Projects/2026/demo_story_2"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectPath))
    }

    func testArchiveCaptureRecordMovesStoredCopyIntoWorkspaceArchiveAndRemovesQueueRecord() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let fileURL = incomingRoot.appendingPathComponent("background_source.pdf")
        try Data("pdf".utf8).write(to: fileURL)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [fileURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let storedPath = try XCTUnwrap(record.importedStoragePath)
        let expectedArchivePath = workspaceRoot
            .appendingPathComponent("Archives", isDirectory: true)
            .appendingPathComponent("Capture archive", isDirectory: true)
            .appendingPathComponent("background_source.pdf")
            .path

        waitForCaptureAsyncWork {
            await store.archiveCaptureRecord(record.id)
        }

        XCTAssertTrue(store.captureRecords.isEmpty)
        XCTAssertEqual(store.captureQueueRecords.count, 0)
        XCTAssertTrue(captureStore.loadRecords()?.isEmpty ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedArchivePath))
    }

    func testCaptureAssignmentTargetsExcludeArchivedProjectsAndKeepOnlyExplicitDossiers() throws {
        let workspaceRoot = try makeWorkspaceRoot(
            includeArea: true,
            includeArchivedProject: true,
            includeNestedAreaReadmes: true
        )
        let discardedProject = workspaceRoot.appendingPathComponent("Projects/2026/discarded_lead")
        try FileManager.default.createDirectory(at: discardedProject, withIntermediateDirectories: true, attributes: nil)
        try """
        ---
        type: project
        project: Discarded Lead
        activity_state: inactive
        workflow_stage: feasibility_study
        inactive_reason: discarded
        status: on_hold
        ---

        # Discarded Lead

        This should stay out of Capture assignment targets.
        """.write(to: discardedProject.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let nonDossierArea = workspaceRoot.appendingPathComponent("Areas/design_area")
        try FileManager.default.createDirectory(at: nonDossierArea, withIntermediateDirectories: true, attributes: nil)
        try """
        # Design Area

        Operational area that should not appear as a dossier target.
        """.write(to: nonDossierArea.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let resourceDossier = workspaceRoot.appendingPathComponent("Resources/straat_van_hormuz")
        try FileManager.default.createDirectory(at: resourceDossier, withIntermediateDirectories: true, attributes: nil)
        try """
        ---
        type: project
        project: Straat van Hormuz
        status: active
        ---

        # Straat van Hormuz

        Reusable dossier material for shipping and energy coverage.
        """.write(to: resourceDossier.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let nonDossierResource = workspaceRoot.appendingPathComponent("Resources/knowledge_base")
        try FileManager.default.createDirectory(at: nonDossierResource, withIntermediateDirectories: true, attributes: nil)
        try """
        # Knowledge base

        Shared operational notes that should stay out of capture assignment.
        """.write(to: nonDossierResource.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let targetTitles = store.captureAssignmentTargets.map(\.title)
        let targetLabels = store.captureAssignmentTargets.map(store.captureAssignmentLabel(for:))
        XCTAssertTrue(targetTitles.contains("Demo Story"))
        XCTAssertTrue(targetTitles.contains("Voedselcrisis 2027"))
        XCTAssertTrue(targetTitles.contains("Straat van Hormuz"))
        XCTAssertFalse(targetTitles.contains("Archived Story"))
        XCTAssertFalse(targetTitles.contains("Discarded Lead"))
        XCTAssertFalse(targetTitles.contains("Area Notes"))
        XCTAssertFalse(targetTitles.contains("Design Area"))
        XCTAssertFalse(targetTitles.contains("Knowledge base"))
        XCTAssertTrue(targetLabels.contains("Demo Story • Active · Investigation"))
        XCTAssertTrue(targetLabels.contains("Voedselcrisis 2027 • Area"))
        XCTAssertTrue(targetLabels.contains("Straat van Hormuz • Resource"))
    }

    func testAssignCaptureRecordCopiesFileIntoTopLevelAreaDocs() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        let incomingRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: incomingRoot, withIntermediateDirectories: true, attributes: nil)
        let fileURL = incomingRoot.appendingPathComponent("area_source.txt")
        try Data("lead".utf8).write(to: fileURL)

        waitForCaptureAsyncWork {
            await store.importCaptureItems(from: [fileURL])
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let area = try XCTUnwrap(store.captureAssignmentTargets.first(where: { $0.section == .areas }))

        waitForCaptureAsyncWork {
            await store.assignCaptureRecord(record.id, to: area, note: "Shared reporting thread.")
        }

        let assigned = try XCTUnwrap(store.captureRecords.first)
        XCTAssertEqual(assigned.state, .assigned)
        XCTAssertEqual(assigned.assignedTargetPath, area.path)
        let destinationPath = try XCTUnwrap(assigned.assignedDestinationPath)
        let factsPath = URL(fileURLWithPath: area.path).appendingPathComponent("docs/facts.md")
        XCTAssertTrue(destinationPath.contains("/Areas/voedselcrisis_2027/docs/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: factsPath.path))
    }

    func testDeleteCaptureRecordRemovesStoredCopyAndQueueRecord() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let supportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let captureStore = CaptureStore(workspaceRoot: workspaceRoot, supportDirectory: supportRoot)
        let store = AppStore(
            configuration: AppConfiguration(
                profile: .standalone,
                workspaceRoot: workspaceRoot,
                demoWorkspaceRoot: nil
            ),
            captureStore: captureStore
        )

        waitForCaptureAsyncWork {
            await store.saveQuickCaptureNote("Delete this temporary capture item.")
        }

        let record = try XCTUnwrap(store.captureRecords.first)
        let storedPath = try XCTUnwrap(record.importedStoragePath)

        waitForCaptureAsyncWork {
            await store.deleteCaptureRecord(record.id)
        }

        XCTAssertTrue(store.captureRecords.isEmpty)
        XCTAssertEqual(store.captureQueueRecords.count, 0)
        XCTAssertTrue(captureStore.loadRecords()?.isEmpty ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedPath))
    }

    func testDefaultOnboardingDraftUsesPersistedDocumentMode() {
        OnboardingPreferences.reset()
        defer { OnboardingPreferences.reset() }

        let defaults = UserDefaults.standard
        defaults.set(OnboardingDocumentMode.googleDocs.rawValue, forKey: OnboardingPreferences.documentModeKey)

        let store = AppStore(configuration: AppConfiguration(
            profile: .standard,
            workspaceRoot: URL(fileURLWithPath: "/tmp/workspace"),
            demoWorkspaceRoot: nil
        ))

        XCTAssertEqual(store.defaultOnboardingDraft.documentMode, .googleDocs)
    }

    func testBeginProjectStatusChangeOpensOffboardingForFinishedStatus() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .done)

        let state = try XCTUnwrap(store.projectStatusChangeState)
        XCTAssertEqual(state.projectTitle, "Demo Story")
        XCTAssertEqual(state.currentCompatibilityStatus, .active)
        XCTAssertEqual(state.targetCompatibilityStatus, .done)
        XCTAssertEqual(state.dossierSlug, "voedselcrisis_2027")
        XCTAssertEqual(state.archiveYear, "2026")
    }

    func testOpenLinkedDossierSelectsMatchingArea() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        let dossier = try XCTUnwrap(store.linkedDossier(for: project))

        store.openLinkedDossier(for: project)

        XCTAssertEqual(store.selection, .workspace(dossier.id))
    }

    func testPuttingProjectOnHoldOpensCanonicalStateEditorBeforeWrite() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .onHold)

        let state = try XCTUnwrap(store.projectDetailsEditState)
        XCTAssertNil(store.projectStatusChangeState)
        XCTAssertEqual(state.currentDisplayTitle, "Demo Story")
        XCTAssertEqual(state.currentProjectType, .journalism)
        XCTAssertEqual(state.currentState.activityState, .active)
        XCTAssertEqual(state.currentState.workflowStage, .activeInvestigation)
        XCTAssertNil(state.currentState.inactiveReason)
        XCTAssertFalse(state.currentIsInDailyFocus)
        XCTAssertEqual(state.initialState.activityState, .inactive)
        XCTAssertEqual(state.initialState.workflowStage, .activeInvestigation)
        XCTAssertEqual(state.initialState.inactiveReason, .waiting)
        XCTAssertFalse(state.initialIsInDailyFocus)

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let unchangedReadmeText = try String(contentsOf: readmePath, encoding: .utf8)
        XCTAssertTrue(unchangedReadmeText.contains("status: active"))

        store.saveProjectDetailsEdit(
            state,
            projectTitle: state.initialDisplayTitle,
            projectType: state.initialProjectType,
            activityState: state.initialState.activityState,
            workflowStage: state.initialState.workflowStage,
            inactiveReason: state.initialState.inactiveReason,
            dossierSlug: state.initialDossierSlug,
            isInDailyFocus: state.initialIsInDailyFocus
        )

        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)

        XCTAssertNil(store.projectDetailsEditState)
        XCTAssertNil(store.projectStatusChangeState)
        XCTAssertTrue(readmeText.contains("activity_state: inactive"))
        XCTAssertTrue(readmeText.contains("workflow_stage: active_investigation"))
        XCTAssertTrue(readmeText.contains("inactive_reason: waiting"))
        XCTAssertTrue(readmeText.contains("status: on_hold"))
    }

    func testDiscardingProjectOpensCanonicalStateEditorBeforeWrite() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginDiscardingProject(project)

        let state = try XCTUnwrap(store.projectDetailsEditState)
        XCTAssertNil(store.projectStatusChangeState)
        XCTAssertEqual(state.currentDisplayTitle, "Demo Story")
        XCTAssertEqual(state.currentProjectType, .journalism)
        XCTAssertEqual(state.currentState.activityState, .active)
        XCTAssertEqual(state.currentState.workflowStage, .activeInvestigation)
        XCTAssertNil(state.currentState.inactiveReason)
        XCTAssertEqual(state.initialState.activityState, .inactive)
        XCTAssertEqual(state.initialState.workflowStage, .activeInvestigation)
        XCTAssertEqual(state.initialState.inactiveReason, .discarded)

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let unchangedReadmeText = try String(contentsOf: readmePath, encoding: .utf8)
        XCTAssertTrue(unchangedReadmeText.contains("status: active"))

        store.saveProjectDetailsEdit(
            state,
            projectTitle: state.initialDisplayTitle,
            projectType: state.initialProjectType,
            activityState: state.initialState.activityState,
            workflowStage: state.initialState.workflowStage,
            inactiveReason: state.initialState.inactiveReason,
            dossierSlug: state.initialDossierSlug,
            isInDailyFocus: state.initialIsInDailyFocus
        )

        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)

        XCTAssertNil(store.projectDetailsEditState)
        XCTAssertTrue(readmeText.contains("activity_state: inactive"))
        XCTAssertTrue(readmeText.contains("workflow_stage: active_investigation"))
        XCTAssertTrue(readmeText.contains("inactive_reason: discarded"))
        XCTAssertTrue(readmeText.contains("status: on_hold"))
    }

    func testEditingProjectDetailsWritesTrustedFrontmatterFields() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectDetailsEditing(for: project)

        let state = try XCTUnwrap(store.projectDetailsEditState)
        XCTAssertEqual(state.currentDossierSlug, "voedselcrisis_2027")
        XCTAssertEqual(state.initialDossierSlug, "voedselcrisis_2027")
        store.saveProjectDetailsEdit(
            state,
            projectTitle: "Retitled Story",
            projectType: .dataJournalism,
            activityState: .inactive,
            workflowStage: .feasibilityStudy,
            inactiveReason: .discarded,
            dossierSlug: state.currentDossierSlug,
            isInDailyFocus: true
        )

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)

        XCTAssertNil(store.projectDetailsEditState)
        XCTAssertTrue(readmeText.contains("project: Retitled Story"))
        XCTAssertTrue(readmeText.contains("project_type: data_journalism"))
        XCTAssertTrue(readmeText.contains("activity_state: inactive"))
        XCTAssertTrue(readmeText.contains("workflow_stage: feasibility_study"))
        XCTAssertTrue(readmeText.contains("inactive_reason: discarded"))
        XCTAssertTrue(readmeText.contains("status: on_hold"))
        XCTAssertTrue(readmeText.contains("daily_focus: true"))
    }

    func testEditingProjectDetailsCanRelinkDossier() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let alternateDossier = workspaceRoot.appendingPathComponent("Resources/straat_van_hormuz")
        try FileManager.default.createDirectory(at: alternateDossier, withIntermediateDirectories: true, attributes: nil)
        try """
        ---
        type: project
        project: Straat van Hormuz
        status: active
        ---

        # Straat van Hormuz

        Resource dossier for energy and shipping coverage.
        """.write(to: alternateDossier.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectDetailsEditing(for: project)

        let state = try XCTUnwrap(store.projectDetailsEditState)
        store.saveProjectDetailsEdit(
            state,
            projectTitle: state.initialDisplayTitle,
            projectType: state.initialProjectType,
            activityState: state.initialState.activityState,
            workflowStage: state.initialState.workflowStage,
            inactiveReason: state.initialState.inactiveReason,
            dossierSlug: "straat_van_hormuz",
            isInDailyFocus: state.initialIsInDailyFocus
        )

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)

        XCTAssertTrue(readmeText.contains("dossier: straat_van_hormuz"))
        XCTAssertFalse(readmeText.contains("dossier: voedselcrisis_2027"))
        let updatedProject = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        XCTAssertEqual(updatedProject.dossierSlug, "straat_van_hormuz")
    }

    func testBeginningProjectDetailsEditingRoutesToProjectPage() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.select(.overview)

        store.beginProjectDetailsEditing(for: project)

        let state = try XCTUnwrap(store.projectDetailsEditState)
        XCTAssertEqual(state.projectID, project.id)
        XCTAssertEqual(store.selection, .workspace(project.id))
    }

    func testTogglingDailyFocusWritesTrustedFrontmatter() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        XCTAssertFalse(project.isInDailyFocus)

        store.toggleDailyFocus(for: project)

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let focusedReadmeText = try String(contentsOf: readmePath, encoding: .utf8)
        XCTAssertTrue(focusedReadmeText.contains("daily_focus: true"))

        let refreshedProject = try XCTUnwrap(store.snapshot.items.first(where: { $0.id == project.id }))
        XCTAssertTrue(refreshedProject.isInDailyFocus)

        store.toggleDailyFocus(for: refreshedProject)

        let unfocusedReadmeText = try String(contentsOf: readmePath, encoding: .utf8)
        XCTAssertFalse(unfocusedReadmeText.contains("daily_focus: true"))
    }

    func testCompletingOffboardingUpdatesStatusAndCopiesPublishedPDF() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .done)
        let state = try XCTUnwrap(store.projectStatusChangeState)

        let sourcePDF = workspaceRoot.appendingPathComponent("published_story.pdf")
        try Data("pdf".utf8).write(to: sourcePDF)

        waitForCaptureAsyncWork {
            await store.completeProjectOffboarding(
                state,
                outcome: .published,
                publishedPDFURL: sourcePDF,
                routeToDossier: true,
                producedSummary: "Published interview and background reporting.",
                remainingOpenSummary: "Track the government's response.",
                impactSummary: "Possible parliamentary questions."
            )
        }

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)
        let importedPDF = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/docs/published_story.pdf")
        let dossierHandoff = workspaceRoot.appendingPathComponent("Areas/voedselcrisis_2027/docs/project_closeouts/demo_story_closeout.md")

        XCTAssertNil(store.projectStatusChangeState)
        XCTAssertTrue(readmeText.contains("activity_state: inactive"))
        XCTAssertTrue(readmeText.contains("workflow_stage: published"))
        XCTAssertTrue(readmeText.contains("inactive_reason: finished"))
        XCTAssertTrue(readmeText.contains("status: done"))
        XCTAssertTrue(readmeText.contains("<!-- project_closeout:start -->"))
        XCTAssertTrue(readmeText.contains("- Activity state: `inactive`"))
        XCTAssertTrue(readmeText.contains("- Workflow stage: `published`"))
        XCTAssertTrue(readmeText.contains("- Outcome: `published`"))
        XCTAssertTrue(readmeText.contains("- Workspace action: Keep project folder in Projects"))
        XCTAssertTrue(readmeText.contains("- Compatibility status: `done`"))
        XCTAssertTrue(readmeText.contains("- Published PDF: `docs/published_story.pdf`"))
        XCTAssertTrue(readmeText.contains("Possible parliamentary questions."))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedPDF.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dossierHandoff.path))
        let dossierHandoffText = try String(contentsOf: dossierHandoff, encoding: .utf8)
        XCTAssertTrue(dossierHandoffText.contains("- Activity state: `inactive`"))
        XCTAssertTrue(dossierHandoffText.contains("- Workflow stage: `published`"))
        XCTAssertTrue(dossierHandoffText.contains("- Workspace action: Keep project folder in Projects"))
        XCTAssertTrue(dossierHandoffText.contains("- Compatibility status: `done`"))
        XCTAssertTrue(store.maintenanceItems.isEmpty)
    }

    func testCompletingOffboardingQueuesMaintenanceForSkippedOptionalFields() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .done)
        let state = try XCTUnwrap(store.projectStatusChangeState)

        waitForCaptureAsyncWork {
            await store.completeProjectOffboarding(
                state,
                outcome: .published,
                publishedPDFURL: nil,
                routeToDossier: false,
                producedSummary: "",
                remainingOpenSummary: "",
                impactSummary: ""
            )
        }

        XCTAssertEqual(Set(store.maintenanceItems.map(\.kind)), Set([
            .missingPublishedPDF,
            .missingProducedSummary,
            .missingRemainingOpen,
            .missingImpactSummary,
            .missingDossierHandoff
        ]))
        XCTAssertEqual(store.overviewOperations.first(where: { $0.id == "workspace-maintenance" })?.count, 5)
    }

    func testCompletingOffboardingRequiresExplicitOutcome() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .archived)
        let state = try XCTUnwrap(store.projectStatusChangeState)
        let originalProjectPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story")
        let archivedProjectPath = workspaceRoot.appendingPathComponent("Archives/2026/demo_story")
        let readmePath = originalProjectPath.appendingPathComponent("README.md")
        let originalReadme = try String(contentsOf: readmePath, encoding: .utf8)

        waitForCaptureAsyncWork {
            await store.completeProjectOffboarding(
                state,
                outcome: .unknown,
                publishedPDFURL: nil,
                routeToDossier: false,
                producedSummary: "",
                remainingOpenSummary: "",
                impactSummary: ""
            )
        }

        let alert = try XCTUnwrap(store.activeAlert)
        let unchangedReadme = try String(contentsOf: readmePath, encoding: .utf8)

        XCTAssertEqual(alert.title, "Outcome required")
        XCTAssertEqual(store.statusMessage, "Choose an explicit offboarding outcome first.")
        XCTAssertNotNil(store.projectStatusChangeState)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalProjectPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivedProjectPath.path))
        XCTAssertEqual(unchangedReadme, originalReadme)
        XCTAssertFalse(unchangedReadme.contains("<!-- project_closeout:start -->"))
    }

    func testArchivingProjectMovesFolderIntoArchiveDestination() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .archived)
        let state = try XCTUnwrap(store.projectStatusChangeState)
        let originalProjectPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story")
        let archivedProjectPath = workspaceRoot.appendingPathComponent("Archives/2026/unpublished/demo_story")

        waitForCaptureAsyncWork {
            await store.completeProjectOffboarding(
                state,
                outcome: .unpublished,
                publishedPDFURL: nil,
                routeToDossier: true,
                producedSummary: "Interview package completed.",
                remainingOpenSummary: "Monitor later developments.",
                impactSummary: "None yet."
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalProjectPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedProjectPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedProjectPath.appendingPathComponent("README.md").path))
        let archivedReadme = try String(contentsOf: archivedProjectPath.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(archivedReadme.contains("activity_state: inactive"))
        XCTAssertTrue(archivedReadme.contains("workflow_stage: active_investigation"))
        XCTAssertTrue(archivedReadme.contains("inactive_reason: finished"))
        XCTAssertTrue(archivedReadme.contains("status: archived"))
        XCTAssertTrue(archivedReadme.contains("- Workspace action: Move project folder into Archives"))
        XCTAssertTrue(archivedReadme.contains("- Compatibility status: `archived`"))
    }

    func testSupersededOffboardingWritesDiscardedInactiveReason() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .archived)
        let state = try XCTUnwrap(store.projectStatusChangeState)
        let archivedProjectPath = workspaceRoot.appendingPathComponent("Archives/2026/unpublished/demo_story")

        waitForCaptureAsyncWork {
            await store.completeProjectOffboarding(
                state,
                outcome: .superseded,
                publishedPDFURL: nil,
                routeToDossier: false,
                producedSummary: "Lead was overtaken by a stronger angle.",
                remainingOpenSummary: "",
                impactSummary: ""
            )
        }

        let archivedReadme = try String(contentsOf: archivedProjectPath.appendingPathComponent("README.md"), encoding: .utf8)

        XCTAssertTrue(archivedReadme.contains("activity_state: inactive"))
        XCTAssertTrue(archivedReadme.contains("workflow_stage: active_investigation"))
        XCTAssertTrue(archivedReadme.contains("inactive_reason: discarded"))
        XCTAssertTrue(archivedReadme.contains("status: archived"))
        XCTAssertTrue(archivedReadme.contains("- Outcome: `superseded`"))
        XCTAssertTrue(archivedReadme.contains("- Inactive reason: `discarded`"))
    }

    func testDeletingArchivedProjectRemovesFolderInsteadOfMovingIt() throws {
        let workspaceRoot = try makeWorkspaceRoot(includeArea: true)
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStatusChange(for: project, targetStatus: .archived)
        let state = try XCTUnwrap(store.projectStatusChangeState)
        let originalProjectPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story")
        let archivedProjectPath = workspaceRoot.appendingPathComponent("Archives/2026/demo_story")
        let unpublishedArchivedProjectPath = workspaceRoot.appendingPathComponent("Archives/2026/unpublished/demo_story")
        let dossierHandoff = workspaceRoot.appendingPathComponent("Areas/voedselcrisis_2027/docs/project_closeouts/demo_story_closeout.md")

        waitForCaptureAsyncWork {
            await store.completeProjectOffboarding(
                state,
                outcome: .deleted,
                publishedPDFURL: nil,
                routeToDossier: true,
                producedSummary: "Throwaway test project.",
                remainingOpenSummary: "",
                impactSummary: ""
            )
        }

        XCTAssertNil(store.projectStatusChangeState)
        XCTAssertEqual(store.statusMessage, "Demo Story deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalProjectPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archivedProjectPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unpublishedArchivedProjectPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dossierHandoff.path))
        XCTAssertTrue(store.maintenanceItems.isEmpty)
    }

    func testImportDocumentsToProjectCopiesIntoDocsFolder() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("transcript.txt")
        try "Interview transcript".write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)

        XCTAssertEqual(importedPaths.count, 1)
        XCTAssertTrue(importedPaths[0].hasSuffix("/Projects/2026/demo_story/docs/transcript.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedPaths[0]))
    }

    func testFinalizeAttachedDocumentsUpdatesDocsOverviewForExistingProject() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("source_note.md")
        try """
        Lead finding from the imported note.

        Supporting detail that should appear in a working summary.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)
        await store.finalizeAttachedDocuments(for: project, importedPaths: importedPaths)

        let overviewPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/docs/docs_overview.md")
        let overviewText = try String(contentsOf: overviewPath, encoding: .utf8)
        let feedback = try XCTUnwrap(store.projectDocumentImportFeedback(for: project))

        XCTAssertTrue(overviewText.contains("## Imported document synthesis"))
        XCTAssertTrue(overviewText.contains("Working summary from source_note.md"))
        XCTAssertEqual(store.statusMessage, "Attached 1 item to Demo Story and updated docs overview")
        XCTAssertEqual(feedback.title, "Docs attached")
        XCTAssertEqual(feedback.style, .success)
        XCTAssertTrue(feedback.showsOpenDocsOverviewAction)
    }

    func testFinalizeAttachedDocumentsPersistsRelevanceNoteInDocsOverview() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("timeline.md")
        try """
        Timeline excerpt for the overnight incident.

        Add this to the working chronology for cross-checking.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)
        await store.finalizeAttachedDocuments(
            for: project,
            importedPaths: importedPaths,
            relevanceNote: "Contains the timeline details we need for the first reconstruction."
        )

        let overviewPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/docs/docs_overview.md")
        let overviewText = try String(contentsOf: overviewPath, encoding: .utf8)
        let feedback = try XCTUnwrap(store.projectDocumentImportFeedback(for: project))

        XCTAssertTrue(overviewText.contains("### Why these files matter now"))
        XCTAssertTrue(overviewText.contains("Contains the timeline details we need for the first reconstruction."))
        XCTAssertEqual(feedback.style, .success)
        XCTAssertTrue(feedback.message.contains("saved your relevance note"))
    }

    func testFinalizeAttachedDocumentsFallsBackWhenModelReturnsInvalidJSON() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FORCE_INVALID_JSON", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FORCE_INVALID_JSON") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("source_note.md")
        try """
        Lead finding from the imported note.

        Supporting detail that should survive the fallback summary path.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)
        await store.finalizeAttachedDocuments(for: project, importedPaths: importedPaths)

        let overviewPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/docs/docs_overview.md")
        let overviewText = try String(contentsOf: overviewPath, encoding: .utf8)
        let feedback = try XCTUnwrap(store.projectDocumentImportFeedback(for: project))

        XCTAssertTrue(overviewText.contains("Fallback summary from source_note.md"))
        XCTAssertTrue(overviewText.contains("parseable JSON"))
        XCTAssertEqual(store.statusMessage, "Attached 1 item to Demo Story and updated docs overview")
        XCTAssertNil(store.activeAlert)
        XCTAssertEqual(feedback.title, "Docs attached")
        XCTAssertEqual(feedback.style, .success)
    }

    func testFinalizeAttachedDocumentsFallbackStillPersistsRelevanceNote() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FORCE_INVALID_JSON", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FORCE_INVALID_JSON") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("background_note.md")
        try """
        Background note for the emissions angle.

        Double-check which figures survive publication review.
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.importDocumentsToProject([sourceFile], item: project)
        await store.finalizeAttachedDocuments(
            for: project,
            importedPaths: importedPaths,
            relevanceNote: "Use this to sanity-check the published numbers before we quote them."
        )

        let overviewPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/docs/docs_overview.md")
        let overviewText = try String(contentsOf: overviewPath, encoding: .utf8)

        XCTAssertTrue(overviewText.contains("Fallback summary from background_note.md"))
        XCTAssertTrue(overviewText.contains("### Why these files matter now"))
        XCTAssertTrue(overviewText.contains("Use this to sanity-check the published numbers before we quote them."))
    }

    func testAttachDocumentsToProjectStartsProjectReviewSession() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let firstFile = workspaceRoot.appendingPathComponent("first_note.md")
        let secondFile = workspaceRoot.appendingPathComponent("second_note.md")
        try "First imported note.".write(to: firstFile, atomically: true, encoding: .utf8)
        try "Second imported note.".write(to: secondFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.attachDocumentsToProject([firstFile, secondFile], item: project)
        let session = try XCTUnwrap(store.activeProjectDocumentReviewSession(for: project))

        XCTAssertEqual(importedPaths.count, 2)
        XCTAssertEqual(session.items.count, 2)
        XCTAssertEqual(session.currentIndex, 0)
        XCTAssertEqual(session.items.first?.sourcePath, firstFile.path)
        XCTAssertEqual(session.items.first?.importedPath, importedPaths.first)
        XCTAssertTrue(store.statusMessage.contains("Review the imported files before updating docs overview"))
    }

    func testPauseProjectDocumentReviewKeepsSessionAvailable() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("hold_for_later.md")
        try "Imported note that can wait.".write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try store.attachDocumentsToProject([sourceFile], item: project)
        store.pauseProjectDocumentReview(for: project)

        XCTAssertNotNil(store.activeProjectDocumentReviewSession(for: project))
        XCTAssertTrue(store.statusMessage.contains("finished later"))
    }

    func testProjectDocumentReviewPreservesSpacesWhileEditingButTrimsOnSave() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("spaced_note.md")
        try "Imported note with spacing.".write(to: sourceFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.attachDocumentsToProject([sourceFile], item: project)
        let importedPath = try XCTUnwrap(importedPaths.first)

        store.updateProjectDocumentReviewNote("Leading and trailing space ", for: importedPath)

        let session = try XCTUnwrap(store.activeProjectDocumentReviewSession(for: project))
        XCTAssertEqual(session.currentItem?.note, "Leading and trailing space ")

        await store.completeProjectDocumentReview(for: project)

        let factsPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs/facts.md")
        let facts = try String(contentsOf: factsPath, encoding: .utf8)

        XCTAssertTrue(facts.contains("Fact: Leading and trailing space"))
        XCTAssertFalse(facts.contains("Fact: Leading and trailing space "))
    }

    func testCompleteProjectDocumentReviewWritesFactsAndPerFileNotes() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let firstFile = workspaceRoot.appendingPathComponent("market_note.md")
        let secondFile = workspaceRoot.appendingPathComponent("policy_note.md")
        try "Market lead for the imported note.".write(to: firstFile, atomically: true, encoding: .utf8)
        try "Policy lead for the imported note.".write(to: secondFile, atomically: true, encoding: .utf8)

        let importedPaths = try store.attachDocumentsToProject([firstFile, secondFile], item: project)
        store.updateProjectDocumentReviewNote("India accounts for 8.9% of EU steel imports.", for: importedPaths[0])
        store.moveToNextProjectDocumentReviewItem()
        store.updateProjectDocumentReviewNote("The CBAM workaround still depends on manual verification.", for: importedPaths[1])

        await store.completeProjectDocumentReview(for: project)

        let factsPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs/facts.md")
        let facts = try String(contentsOf: factsPath, encoding: .utf8)
        let overviewPath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/docs/docs_overview.md")
        let overview = try String(contentsOf: overviewPath, encoding: .utf8)
        let feedback = try XCTUnwrap(store.projectDocumentImportFeedback(for: project))

        XCTAssertNil(store.activeProjectDocumentReviewSession(for: project))
        XCTAssertTrue(facts.contains("Fact: India accounts for 8.9% of EU steel imports."))
        XCTAssertTrue(facts.contains("Fact: The CBAM workaround still depends on manual verification."))
        XCTAssertTrue(overview.contains("- Note: India accounts for 8.9% of EU steel imports."))
        XCTAssertTrue(overview.contains("- Note: The CBAM workaround still depends on manual verification."))
        XCTAssertTrue(feedback.message.contains("saved 2 review notes to facts"))
    }

    func testCompleteProjectDocumentReviewSkipsEmptyFactsEntries() async throws {
        setenv("JWH_SCAFFOLD_SUMMARY_FAKE", "1", 1)
        defer { unsetenv("JWH_SCAFFOLD_SUMMARY_FAKE") }

        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))
        let project = try XCTUnwrap(store.snapshot.items.first)

        let sourceFile = workspaceRoot.appendingPathComponent("empty_note.md")
        try "Imported note without extra annotation.".write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try store.attachDocumentsToProject([sourceFile], item: project)
        await store.completeProjectDocumentReview(for: project)

        let factsPath = URL(fileURLWithPath: project.path).appendingPathComponent("docs/facts.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: factsPath.path))
    }

    private func waitForCaptureAsyncWork(_ operation: @escaping @MainActor () async -> Void) {
        let expectation = expectation(description: "async capture work")
        Task {
            await operation()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
    }

    private func makeWorkspaceRoot(
        includeArea: Bool = false,
        includeArchivedProject: Bool = false,
        includeNestedAreaReadmes: Bool = false
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = tmp.appendingPathComponent("Projects/2026/demo_story")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true, attributes: nil)

        try """
        ---
        type: project
        project: Demo Story
        status: active
        project_type: journalism
        dossier: voedselcrisis_2027
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

        if includeArea {
            let area = tmp.appendingPathComponent("Areas/voedselcrisis_2027")
            try FileManager.default.createDirectory(at: area, withIntermediateDirectories: true, attributes: nil)
            try """
            ---
            type: project
            project: voedselcrisis_2027
            status: active
            ---

            # Voedselcrisis 2027

            Broader area for exploring possible reporting angles.
            """.write(to: area.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

            if includeNestedAreaReadmes {
                let nestedAreaDocs = area.appendingPathComponent("docs/hubs", isDirectory: true)
                try FileManager.default.createDirectory(at: nestedAreaDocs, withIntermediateDirectories: true, attributes: nil)
                try """
                # Area Notes

                Nested notes should not appear as assignment targets.
                """.write(to: nestedAreaDocs.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            }
        }

        if includeArchivedProject {
            let archivedProject = tmp.appendingPathComponent("Archives/2025/archived_story")
            try FileManager.default.createDirectory(at: archivedProject, withIntermediateDirectories: true, attributes: nil)
            try """
            ---
            type: project
            project: Archived Story
            status: archived
            ---

            # Archived Story

            This should stay out of Capture assignment targets.
            """.write(to: archivedProject.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        }

        return tmp
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
