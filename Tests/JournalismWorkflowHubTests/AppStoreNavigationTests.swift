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
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
        XCTAssertTrue(destinationPath.contains("/docs/"))
        XCTAssertEqual(store.captureQueueRecords.count, 0)
        XCTAssertEqual(store.captureAssignedRecords.count, 1)
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
        XCTAssertTrue(readme.contains("project: Inspectors ignored repeated warning signs"))
        XCTAssertTrue(readme.contains("deliverable: Placeholder lead from Capture. Confirm the reporting angle later."))

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

    func testCaptureAssignmentTargetsExcludeArchivedProjectsAndIncludeTopLevelAreas() throws {
        let workspaceRoot = try makeWorkspaceRoot(
            includeArea: true,
            includeArchivedProject: true,
            includeNestedAreaReadmes: true
        )
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let targetTitles = store.captureAssignmentTargets.map(\.title)
        XCTAssertTrue(targetTitles.contains("Demo Story"))
        XCTAssertTrue(targetTitles.contains("Voedselcrisis 2027"))
        XCTAssertFalse(targetTitles.contains("Archived Story"))
        XCTAssertFalse(targetTitles.contains("Area Notes"))
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
        XCTAssertTrue(destinationPath.contains("/Areas/voedselcrisis_2027/docs/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationPath))
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
        XCTAssertEqual(state.currentStatus, .active)
        XCTAssertEqual(state.targetStatus, .done)
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

    func testPuttingProjectOnHoldUpdatesReadmeStatus() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        waitForCaptureAsyncWork {
            store.beginProjectStatusChange(for: project, targetStatus: .onHold)
        }

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md").path
        let readmeText = try String(contentsOfFile: readmePath, encoding: .utf8)

        XCTAssertNil(store.projectStatusChangeState)
        XCTAssertTrue(readmeText.contains("activity_state: inactive"))
        XCTAssertTrue(readmeText.contains("workflow_stage: active_investigation"))
        XCTAssertTrue(readmeText.contains("inactive_reason: waiting"))
        XCTAssertTrue(readmeText.contains("status: on_hold"))
    }

    func testEditingProjectStateWritesNewFrontmatterFields() throws {
        let workspaceRoot = try makeWorkspaceRoot()
        let store = AppStore(configuration: AppConfiguration(
            profile: .standalone,
            workspaceRoot: workspaceRoot,
            demoWorkspaceRoot: nil
        ))

        let project = try XCTUnwrap(store.snapshot.items.first(where: { $0.section == .projects }))
        store.beginProjectStateEditing(for: project)

        let state = try XCTUnwrap(store.projectStateEditState)
        store.saveProjectStateEdit(
            state,
            activityState: .inactive,
            workflowStage: .feasibilityStudy,
            inactiveReason: .discarded
        )

        let readmePath = workspaceRoot.appendingPathComponent("Projects/2026/demo_story/README.md")
        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)

        XCTAssertNil(store.projectStateEditState)
        XCTAssertTrue(readmeText.contains("activity_state: inactive"))
        XCTAssertTrue(readmeText.contains("workflow_stage: feasibility_study"))
        XCTAssertTrue(readmeText.contains("inactive_reason: discarded"))
        XCTAssertTrue(readmeText.contains("status: on_hold"))
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
