import SwiftUI
import AppKit

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case startMode
    case documentMode
    case workspaceLocation
    case workspaceSetup
    case finish

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .startMode:
            return "How do you want to start?"
        case .documentMode:
            return "How do you handle documents?"
        case .workspaceLocation:
            return "Where should the workspace live?"
        case .workspaceSetup:
            return "Workspace setup"
        case .finish:
            return "Ready to start"
        }
    }
}

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: AppStore
    let onFinished: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var draft = OnboardingDraft.initial(defaultNewWorkspacePath: defaultNewWorkspacePath())
    @State private var didLoadDefaults = false
    @State private var errorMessage: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.93, blue: 0.88),
                        Color(red: 0.88, green: 0.92, blue: 0.87),
                        Color(red: 0.84, green: 0.90, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    onboardingHeader
                    contentCard(availableHeight: proxy.size.height)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onAppear {
            guard !didLoadDefaults else { return }
            didLoadDefaults = true
            draft = store.defaultOnboardingDraft
        }
        .alert("Setup issue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("First-run setup")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.20, green: 0.28, blue: 0.28))
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline) {
                Text(step.title)
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.18))
                Spacer()
                Text("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(red: 0.27, green: 0.34, blue: 0.34))
            }

            ProgressView(value: Double(step.rawValue + 1), total: Double(OnboardingStep.allCases.count))
                .tint(Color(red: 0.16, green: 0.27, blue: 0.27))
        }
        .frame(maxWidth: 780, alignment: .leading)
    }

    private func contentCard(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView {
                Group {
                    switch step {
                    case .welcome:
                        welcomeStep
                    case .startMode:
                        startModeStep
                    case .documentMode:
                        documentModeStep
                    case .workspaceLocation:
                        workspaceLocationStep
                    case .workspaceSetup:
                        workspaceSetupStep
                    case .finish:
                        finishStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: max(220, availableHeight - 260))

            Divider()
                .overlay(Color.white.opacity(0.45))

            HStack {
                Button("Back") {
                    moveBackward()
                }
                .disabled(step == .welcome)

                Spacer()

                Button(step == .finish ? "Finish setup" : "Continue") {
                    continueFromCurrentStep()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.15, green: 0.25, blue: 0.24))
                .disabled(!canContinue)
            }
        }
        .padding(30)
        .frame(maxWidth: 780, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Journalism Workflow Hub is a local-first newsroom control surface. It reads your reporting workspace, shows what matters now, and runs trusted local workflows without turning your files into a hidden cloud system.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))

            VStack(alignment: .leading, spacing: 10) {
                onboardingBullet("The app reads local folders such as `Projects`, `Areas`, `Resources`, and `Archives`.")
                onboardingBullet("It can work with plain local files immediately.")
                onboardingBullet("Google Doc pointers are partially supported; other sync providers can still work if they sync to a local folder.")
                onboardingBullet("Some advanced workflows still depend on local tooling and may stay unavailable until configured.")
            }
        }
    }

    private var startModeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the cleanest start for this machine. You can always change the workspace later.")
                .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))

            ForEach(OnboardingStartMode.allCases, id: \.self) { mode in
                ChoiceCard(
                    title: mode.label,
                    summary: mode.summary,
                    isSelected: draft.startMode == mode
                ) {
                    draft.startMode = mode
                    draft.confirmedSeparateWorkspaceCreation = false
                    switch mode {
                    case .demo:
                        draft.firstAction = .inspectFirstProject
                    case .existingWorkspace:
                        if draft.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            draft.workspacePath = store.workspaceRoot.path
                        }
                    case .createWorkspace:
                        if draft.workspacePath == store.workspaceRoot.path || draft.workspacePath.isEmpty {
                            draft.workspacePath = defaultNewWorkspacePath()
                        }
                        draft.createBaseStructure = true
                    }
                }
            }
        }
    }

    private var documentModeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This sets expectations for the first run. It does not lock the app into one provider forever.")
                .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))

            ForEach(OnboardingDocumentMode.allCases, id: \.self) { mode in
                ChoiceCard(
                    title: mode.label,
                    summary: mode.summary,
                    isSelected: draft.documentMode == mode
                ) {
                    draft.documentMode = mode
                }
            }
        }
    }

    private var workspaceLocationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch draft.startMode {
            case .demo:
                Text("The demo workspace is bundled with the app. It opens in standalone mode and hides local-only newsroom workflows by default.")
                    .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))

                if let demoRoot = store.demoWorkspaceRoot {
                    pathPreview(demoRoot.path)
                }
            case .existingWorkspace:
                Text("Point the app at the root folder of an existing workspace.")
                    .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
                workspacePathEditor(
                    label: "Existing workspace root",
                    browseLabel: "Choose workspace…"
                )
            case .createWorkspace:
                Text("Choose where the new workspace should be created. The default keeps the first setup obvious and easy to inspect.")
                    .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
                workspacePathEditor(
                    label: "New workspace root",
                    browseLabel: "Choose parent folder…"
                )
            }
        }
    }

    private var workspaceSetupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch draft.startMode {
            case .demo:
                Text("The demo workspace already contains a sample project and the standard folder structure.")
                    .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
                capabilityIssueList(issues: demoSetupMessages)
            case .existingWorkspace:
                Text("The app checks for the folders it needs at the root of the selected workspace.")
                    .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
                capabilityIssueList(issues: validationReport.issues)
            case .createWorkspace:
                Toggle(isOn: $draft.createBaseStructure) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create the base workspace structure for me")
                            .font(.headline)
                        Text("This creates `Projects`, `Areas`, `Resources`, `Archives`, plus starter `README.md` and `AGENTS.md` files.")
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.30, green: 0.37, blue: 0.37))
                    }
                }
                .toggleStyle(.switch)

                if selectedCreateWorkspaceAlreadyLooksValid {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This path already looks like a working workspace.")
                            .font(.headline)
                        Text("Use that folder as an existing workspace instead of setting up another project root on top of it.")
                            .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
                        Button("Use this as existing workspace") {
                            draft.startMode = .existingWorkspace
                            draft.confirmedSeparateWorkspaceCreation = false
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else if draft.needsSeparateWorkspaceConfirmation(
                    configuredWorkspacePath: currentWorkspacePath,
                    configuredWorkspaceLooksValid: currentWorkspaceLooksValid
                ) {
                    Toggle(isOn: $draft.confirmedSeparateWorkspaceCreation) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I want to set up another workspace")
                                .font(.headline)
                            Text("You already have a usable workspace at `\(currentWorkspacePath)`. Only continue if you really want a separate workspace root.")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.30, green: 0.37, blue: 0.37))
                        }
                    }
                    .toggleStyle(.switch)
                }

                capabilityIssueList(issues: createSetupMessages)
            }
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("This is what the first usable state will look like after setup.")
                .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))

            VStack(alignment: .leading, spacing: 10) {
                capabilityPill("Start mode", value: draft.startMode.label)
                capabilityPill("Documents", value: draft.documentMode.label)
                capabilityPill("Profile", value: draft.startMode == .demo ? AppProfile.standalone.label : AppProfile.standard.label)
                capabilityPill("Workspace", value: finishWorkspacePath)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Capability check")
                    .font(.headline)
                capabilityIssueList(issues: finishMessages)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What should happen first?")
                    .font(.headline)
                ForEach(availableFirstActions, id: \.self) { action in
                    ChoiceCard(
                        title: action.label,
                        summary: firstActionSummary(action),
                        isSelected: draft.firstAction == action
                    ) {
                        draft.firstAction = action
                    }
                }
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .welcome, .startMode, .documentMode:
            return true
        case .workspaceLocation:
            switch draft.startMode {
            case .demo:
                return true
            case .existingWorkspace, .createWorkspace:
                return !draft.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .workspaceSetup:
            switch draft.startMode {
            case .demo:
                return true
            case .existingWorkspace:
                return validationReport.isValid
            case .createWorkspace:
                return draft.canProceedWithNewWorkspaceCreation(
                    selectedPathAlreadyLooksLikeWorkspace: selectedCreateWorkspaceAlreadyLooksValid,
                    needsExtraConfirmation: draft.needsSeparateWorkspaceConfirmation(
                        configuredWorkspacePath: currentWorkspacePath,
                        configuredWorkspaceLooksValid: currentWorkspaceLooksValid
                    )
                )
            }
        case .finish:
            return true
        }
    }

    private var validationReport: WorkspaceValidationReport {
        let path = draft.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: path.isEmpty ? "/" : path)
        return WorkspaceStructureValidator.validateExistingWorkspace(at: url)
    }

    private var demoSetupMessages: [WorkspaceValidationIssue] {
        [
            .init(severity: .info, message: "The demo workspace already contains `Projects`, `Areas`, `Resources`, and `Archives`."),
            .init(severity: .info, message: "Portable workflows remain visible; local newsroom workflows stay hidden in standalone mode.")
        ]
    }

    private var createSetupMessages: [WorkspaceValidationIssue] {
        var issues: [WorkspaceValidationIssue] = [
            .init(severity: .info, message: "The app will create the standard root folders and starter guidance files."),
            .init(severity: .warning, message: "Advanced Python-backed workflows will still need additional local tooling later.")
        ]

        if selectedCreateWorkspaceAlreadyLooksValid {
            issues.insert(
                .init(severity: .blocking, message: "The selected path already looks like a working workspace. Switch to `Use existing workspace` instead."),
                at: 0
            )
        } else if draft.needsSeparateWorkspaceConfirmation(
            configuredWorkspacePath: currentWorkspacePath,
            configuredWorkspaceLooksValid: currentWorkspaceLooksValid
        ) {
            issues.insert(
                .init(severity: .warning, message: "A usable workspace already exists at `\(currentWorkspacePath)`. Confirm explicitly before creating another one."),
                at: 0
            )
        }

        return issues
    }

    private var finishMessages: [WorkspaceValidationIssue] {
        var issues: [WorkspaceValidationIssue] = []

        switch draft.startMode {
        case .demo:
            issues.append(.init(severity: .info, message: "The app will open the bundled demo workspace in standalone mode."))
            issues.append(.init(severity: .info, message: "Local-only newsroom workflows stay hidden until a real workspace is connected."))
        case .existingWorkspace:
            if validationReport.isValid {
                issues.append(.init(severity: .info, message: "The selected workspace has the required base folders."))
            }
            issues.append(contentsOf: validationReport.warnings)
        case .createWorkspace:
            issues.append(.init(severity: .info, message: "The app will create a fresh workspace with the standard folder structure."))
        }

        switch draft.documentMode {
        case .localOnly:
            issues.append(.init(severity: .info, message: "Plain local file workflows will work immediately."))
        case .googleDocs:
            issues.append(.init(severity: .warning, message: "Google Doc pointers and cache status are supported, but deeper provider flows are still limited."))
        case .otherSync:
            issues.append(.init(severity: .warning, message: "Other sync providers work only through their locally synced folders for now."))
        }

        issues.append(.init(severity: .warning, message: "Some advanced workflows may remain unavailable until their local tools are installed."))
        return issues
    }

    private var currentWorkspacePath: String {
        store.workspaceRoot.path
    }

    private var currentWorkspaceLooksValid: Bool {
        !store.isUsingDemoWorkspace
            && WorkspaceStructureValidator.looksLikeExistingWorkspace(at: store.workspaceRoot)
    }

    private var selectedCreateWorkspaceAlreadyLooksValid: Bool {
        guard draft.startMode == .createWorkspace else { return false }
        let path = draft.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return WorkspaceStructureValidator.looksLikeExistingWorkspace(at: url)
    }

    private var availableFirstActions: [OnboardingFirstAction] {
        let profile: AppProfile = draft.startMode == .demo ? .standalone : .standard
        return draft.availableFirstActions(using: profile)
    }

    private var finishWorkspacePath: String {
        switch draft.startMode {
        case .demo:
            return store.demoWorkspaceRoot?.path ?? "Bundled demo workspace"
        case .existingWorkspace, .createWorkspace:
            return draft.workspacePath
        }
    }

    private func firstActionSummary(_ action: OnboardingFirstAction) -> String {
        switch action {
        case .openOverview:
            return "Land on the overview screen and inspect the workspace from there."
        case .inspectFirstProject:
            return "Jump directly to the first detected project or sample project."
        case .startNewProject:
            return "Open the scaffold-project workflow immediately after setup."
        }
    }

    private func workspacePathEditor(label: String, browseLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.headline)

            HStack(spacing: 10) {
                TextField("", text: Binding(
                    get: { draft.workspacePath },
                    set: { newValue in
                        draft.workspacePath = newValue
                        if draft.startMode == .createWorkspace {
                            draft.confirmedSeparateWorkspaceCreation = false
                        }
                    }
                ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button(browseLabel) {
                    chooseDirectory()
                }
            }
        }
    }

    private func pathPreview(_ path: String) -> some View {
        Text(path)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func capabilityIssueList(issues: [WorkspaceValidationIssue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(issueColor(issue.severity))
                        .frame(width: 9, height: 9)
                        .padding(.top, 6)
                    Text(issue.message)
                        .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
                }
            }
        }
    }

    private func capabilityPill(_ title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.25, green: 0.32, blue: 0.32))
                .textCase(.uppercase)
            Text(value)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color(red: 0.14, green: 0.20, blue: 0.20))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55), in: Capsule())
    }

    private func onboardingBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(red: 0.16, green: 0.27, blue: 0.27))
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            Text(text)
                .foregroundStyle(Color(red: 0.18, green: 0.25, blue: 0.25))
        }
    }

    private func issueColor(_ severity: WorkspaceValidationSeverity) -> Color {
        switch severity {
        case .blocking:
            return .red
        case .warning:
            return .orange
        case .info:
            return .green
        }
    }

    private func moveBackward() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func continueFromCurrentStep() {
        if step == .finish {
            do {
                try store.completeOnboarding(using: draft)
                onFinished()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        let path = draft.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }

        if panel.runModal() == .OK, let url = panel.url {
            switch draft.startMode {
            case .createWorkspace:
                let currentName = URL(fileURLWithPath: draft.workspacePath).lastPathComponent
                let suggestedName = currentName.isEmpty ? "JournalismWorkflowHub" : currentName
                draft.workspacePath = url.appendingPathComponent(suggestedName, isDirectory: true).path
                draft.confirmedSeparateWorkspaceCreation = false
            case .demo, .existingWorkspace:
                draft.workspacePath = url.path
            }
        }
    }
}

private struct ChoiceCard: View {
    let title: String
    let summary: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.13, green: 0.18, blue: 0.18))
                    Text(summary)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color(red: 0.28, green: 0.35, blue: 0.35))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color(red: 0.14, green: 0.25, blue: 0.24) : Color(red: 0.55, green: 0.60, blue: 0.60))
            }
            .padding(18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: Color {
        isSelected ? Color.white.opacity(0.75) : Color.white.opacity(0.45)
    }

    private var cardBorder: Color {
        isSelected ? Color(red: 0.15, green: 0.25, blue: 0.24) : Color.white.opacity(0.55)
    }
}
