import SwiftUI
import AppKit

enum ScaffoldProjectWizardStep: Int, CaseIterable, Hashable {
    case workingTitle
    case projectKind
    case startingPoint
    case pitch
    case summary
    case structure
    case sourceMaterial
    case priority
    case review

    var title: String {
        switch self {
        case .workingTitle:
            return "Working title"
        case .projectKind:
            return "Project kind"
        case .startingPoint:
            return "Starting point"
        case .pitch:
            return "Pitch or brief"
        case .summary:
            return "Project summary"
        case .structure:
            return "First structure"
        case .sourceMaterial:
            return "Source material"
        case .priority:
            return "Priority"
        case .review:
            return "Review and create"
        }
    }
}

enum ScaffoldProjectKind: String, CaseIterable, Hashable {
    case journalism
    case dataJournalism
    case privateCoding
    case other

    var label: String {
        switch self {
        case .journalism:
            return "Journalism"
        case .dataJournalism:
            return "Data journalism"
        case .privateCoding:
            return "Private coding project"
        case .other:
            return "Other"
        }
    }

    var summary: String {
        switch self {
        case .journalism:
            return "A reporting project that is likely to become a story."
        case .dataJournalism:
            return "A reporting project centered on collecting, transforming, and analyzing data."
        case .privateCoding:
            return "A private build, prototype, or technical tool that supports your work."
        case .other:
            return "Something outside the usual reporting or tooling buckets."
        }
    }
}

enum ScaffoldSourceMaterialChoice: String, CaseIterable, Hashable {
    case now
    case later

    var label: String {
        switch self {
        case .now:
            return "Yes, add documents now"
        case .later:
            return "Not now"
        }
    }

    var summary: String {
        switch self {
        case .now:
            return "Create the project first, then move into a follow-up import step."
        case .later:
            return "Keep the intake fast and add source material after the scaffold is ready."
        }
    }
}

enum ScaffoldProjectPriority: String, CaseIterable, Hashable {
    case low
    case normal
    case high

    var label: String {
        rawValue.capitalized
    }

    var summary: String {
        switch self {
        case .low:
            return "Useful to capture now, but not urgent."
        case .normal:
            return "Active work, but not under immediate pressure."
        case .high:
            return "Needs attention soon and should stay visible in planning."
        }
    }
}

struct ScaffoldProjectWizardDraft: Hashable {
    var workingTitle: String = ""
    var projectKind: ScaffoldProjectKind = .journalism
    var customProjectKind: String = ""
    var hasPitch: Bool?
    var pitchText: String = ""
    var summaryText: String = ""
    var sourceMaterialChoice: ScaffoldSourceMaterialChoice?
    var priority: ScaffoldProjectPriority = .normal
    var folderNameOverride: String = ""
    var projectRootOverride: String = ""
    var topics: String = ""
    var entities: String = ""
    var structureAnswerOne: String = ""
    var structureAnswerTwo: String = ""
    var structureAnswerThree: String = ""

    mutating func syncAdvancedDefaults(workspaceRoot: URL) {
        guard !trimmedTitle.isEmpty else { return }

        if folderNameOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            folderNameOverride = derivedFolderName
        }
        if projectRootOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projectRootOverride = derivedProjectRoot(workspaceRoot: workspaceRoot)
        }
    }

    mutating func updateWorkingTitle(_ newValue: String, workspaceRoot: URL) {
        let previousTitle = workingTitle
        let previousFolderOverride = folderNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousProjectRootOverride = projectRootOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousDerivedFolderName = normalizedProjectSlug(previousTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        let previousDerivedProjectRoot = workspaceRoot
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(currentProjectYear(), isDirectory: true)
            .appendingPathComponent(previousDerivedFolderName, isDirectory: true)
            .path

        workingTitle = newValue
        let nextDerivedFolderName = normalizedProjectSlug(newValue.trimmingCharacters(in: .whitespacesAndNewlines))

        if previousFolderOverride.isEmpty || previousFolderOverride == previousDerivedFolderName {
            folderNameOverride = nextDerivedFolderName
        }

        if previousProjectRootOverride.isEmpty || previousProjectRootOverride == previousDerivedProjectRoot {
            if nextDerivedFolderName.isEmpty {
                projectRootOverride = ""
            } else {
                projectRootOverride = workspaceRoot
                    .appendingPathComponent("Projects", isDirectory: true)
                    .appendingPathComponent(currentProjectYear(), isDirectory: true)
                    .appendingPathComponent(nextDerivedFolderName, isDirectory: true)
                    .path
            }
        }
    }

    mutating func updateFolderNameOverride(_ newValue: String, workspaceRoot: URL) {
        let previousProjectRootOverride = projectRootOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousDerivedProjectRoot = derivedProjectRoot(workspaceRoot: workspaceRoot)

        folderNameOverride = newValue

        if previousProjectRootOverride.isEmpty || previousProjectRootOverride == previousDerivedProjectRoot {
            let normalizedFolderName = normalizedProjectSlug(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            if normalizedFolderName.isEmpty {
                projectRootOverride = ""
            } else {
                projectRootOverride = workspaceRoot
                    .appendingPathComponent("Projects", isDirectory: true)
                    .appendingPathComponent(currentProjectYear(), isDirectory: true)
                    .appendingPathComponent(normalizedFolderName, isDirectory: true)
                    .path
            }
        }
    }

    var trimmedTitle: String {
        workingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPitch: String {
        pitchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedSummary: String {
        summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStructureAnswerOne: String {
        structureAnswerOne.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStructureAnswerTwo: String {
        structureAnswerTwo.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedStructureAnswerThree: String {
        structureAnswerThree.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var requiresSummaryStructuring: Bool {
        trimmedPitch.isEmpty && !trimmedSummary.isEmpty
    }

    var hasCompletedSummaryStructuring: Bool {
        !trimmedStructureAnswerOne.isEmpty
            && !trimmedStructureAnswerTwo.isEmpty
            && !trimmedStructureAnswerThree.isEmpty
    }

    var hasUsableDerivedFolderName: Bool {
        !derivedFolderName.isEmpty
    }

    var derivedFolderName: String {
        let override = folderNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            return normalizedProjectSlug(override)
        }
        return normalizedProjectSlug(trimmedTitle)
    }

    func derivedProjectRoot(workspaceRoot: URL) -> String {
        let override = projectRootOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            return override
        }
        guard !derivedFolderName.isEmpty else {
            return ""
        }
        return workspaceRoot
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(currentProjectYear(), isDirectory: true)
            .appendingPathComponent(derivedFolderName, isDirectory: true)
            .path
    }

    var deliverableText: String {
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }
        return trimmedPitch
    }

    var projectKindLabel: String {
        if projectKind == .other {
            let trimmed = customProjectKind.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? projectKind.label : trimmed
        }
        return projectKind.label
    }

    func mappedState(for workflow: WorkflowDefinition, workspaceRoot: URL) -> WorkflowParameterState {
        var state = WorkflowParameterState()
        state.applyDefaults(from: workflow.parameters)
        state.textValues["project_root"] = derivedProjectRoot(workspaceRoot: workspaceRoot)
        state.textValues["title"] = trimmedTitle
        state.textValues["owner"] = defaultProjectOwner(existingValue: state.textValues["owner"])
        state.textValues["status"] = "active"
        state.textValues["project_type"] = mappedProjectType
        state.textValues["started"] = currentProjectDate()
        state.textValues["deliverable"] = deliverableText
        state.textValues["topics"] = topics.trimmingCharacters(in: .whitespacesAndNewlines)
        state.textValues["entities"] = entities.trimmingCharacters(in: .whitespacesAndNewlines)
        state.textValues["section_answer_1"] = trimmedStructureAnswerOne
        state.textValues["section_answer_2"] = trimmedStructureAnswerTwo
        state.textValues["section_answer_3"] = trimmedStructureAnswerThree
        return state
    }

    var mappedProjectType: String {
        switch projectKind {
        case .journalism:
            return "journalism"
        case .dataJournalism:
            return "data_journalism"
        case .privateCoding:
            return "tooling"
        case .other:
            return "general"
        }
    }
}

struct ScaffoldProjectWizardView: View {
    @EnvironmentObject private var store: AppStore
    @FocusState private var focusedField: FocusField?
    @State private var existingPathConflict: ExistingPathConflict?

    let workflow: WorkflowDefinition

    private enum FocusField: Hashable {
        case workingTitle
    }

    var body: some View {
        let activeSteps = orderedSteps
        let currentStep = currentWizardStep

        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "New project") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Create a project through a short Q&A instead of a dense setup form.")
                            .foregroundStyle(AppPalette.subtle)
                        ProgressView(value: Double(stepIndex(in: activeSteps) + 1), total: Double(activeSteps.count))
                            .tint(AppPalette.title)
                        Text("\(stepIndex(in: activeSteps) + 1) of \(activeSteps.count) • \(currentStep.title)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.subtle)
                    }

                    stepBody(for: currentStep)

                    Divider()

                    HStack {
                        Button("Back") {
                            moveBackward()
                        }
                        .disabled(currentStep == activeSteps.first)

                        Spacer()

                        Button(currentStep == .review ? "Create project" : "Continue") {
                            currentStep == .review ? createProject() : moveForward()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(primaryActionDisabled(for: currentStep))
                    }
                }
            }
        }
        .onAppear {
            if store.scaffoldProjectWizardDraft.workingTitle.isEmpty,
               store.scaffoldProjectWizardDraft.folderNameOverride.isEmpty,
               store.scaffoldProjectWizardDraft.projectRootOverride.isEmpty {
                store.scaffoldProjectWizardDraft.syncAdvancedDefaults(workspaceRoot: store.workspaceRoot)
            }
            focusCurrentStep()
        }
        .onChange(of: store.scaffoldProjectWizardStep, initial: false) { _, _ in
            focusCurrentStep()
        }
        .alert(item: $existingPathConflict) { conflict in
            switch conflict.kind {
            case .reuseProject:
                return Alert(
                    title: Text("Project already exists"),
                    message: Text("A project with this working title already exists in \(conflict.path). Do you want to keep working from that directory and add new documents there?"),
                    primaryButton: .default(Text("Use existing project")) {
                        guard let sourceMaterialChoice = draft.sourceMaterialChoice else { return }
                        store.reuseExistingScaffoldProject(
                            projectTitle: draft.trimmedTitle,
                            projectRoot: conflict.path,
                            sourceMaterialChoice: sourceMaterialChoice
                        )
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            case .existingFolder:
                return Alert(
                    title: Text("Folder already exists"),
                    message: Text("The folder \(conflict.path) already exists but does not look like a reusable project root. Change the folder name in Advanced details before creating the project."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var currentWizardStep: ScaffoldProjectWizardStep {
        store.scaffoldProjectWizardStep
    }

    private var draft: ScaffoldProjectWizardDraft {
        get { store.scaffoldProjectWizardDraft }
        nonmutating set { store.scaffoldProjectWizardDraft = newValue }
    }

    private var orderedSteps: [ScaffoldProjectWizardStep] {
        var steps: [ScaffoldProjectWizardStep] = [
            .workingTitle,
            .projectKind,
            .startingPoint
        ]

        if draft.hasPitch == true {
            steps.append(.pitch)
            if draft.trimmedPitch.isEmpty || currentWizardStep == .summary {
                steps.append(.summary)
            }
        } else if draft.hasPitch == false {
            steps.append(.summary)
        }

        if draft.hasPitch != nil {
            if draft.requiresSummaryStructuring || currentWizardStep == .structure {
                steps.append(.structure)
            }
            steps.append(contentsOf: [.sourceMaterial, .priority, .review])
        }

        return steps
    }

    private var mappedState: WorkflowParameterState {
        draft.mappedState(for: workflow, workspaceRoot: store.workspaceRoot)
    }

    private var preflightReport: WorkflowPreflightReport {
        WorkflowPreflightEvaluator.evaluate(
            workflow: workflow,
            workspaceRoot: store.workspaceRoot,
            selection: store.selectedWorkspaceItem,
            state: mappedState
        )
    }

    private var commandPreview: String {
        do {
            let resolved = try WorkflowRegistry(workspaceRoot: store.workspaceRoot, appProfile: store.appProfile).resolveCommand(
                workflow: workflow,
                state: mappedState,
                selection: store.selectedWorkspaceItem
            )
            return [
                "cd \(resolved.workingDirectory)",
                resolved.commandPreview
            ].joined(separator: "\n")
        } catch {
            return error.localizedDescription
        }
    }

    private func stepIndex(in steps: [ScaffoldProjectWizardStep]) -> Int {
        steps.firstIndex(of: currentWizardStep) ?? 0
    }

    @ViewBuilder
    private func stepBody(for step: ScaffoldProjectWizardStep) -> some View {
        switch step {
        case .workingTitle:
            promptLayout(
                question: "What is the working title of this project?",
                helper: "Start with the human-facing title. The folder name can be adjusted later."
            ) {
                TextField("Working title", text: binding(\.workingTitle))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .workingTitle)

                if !draft.trimmedTitle.isEmpty && !draft.hasUsableDerivedFolderName {
                    Text("Use at least one letter or number so the app can derive a local folder name.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        case .projectKind:
            promptLayout(
                question: "What kind of project is this?",
                helper: "This keeps the intake legible now and leaves room for deeper lifecycle defaults later."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ScaffoldProjectKind.allCases, id: \.self) { kind in
                        WizardChoiceCard(
                            title: kind.label,
                            summary: kind.summary,
                            isSelected: draft.projectKind == kind
                        ) {
                            draft.projectKind = kind
                        }
                    }

                    if draft.projectKind == .other {
                        TextField("Optional custom label", text: binding(\.customProjectKind))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        case .startingPoint:
            promptLayout(
                question: "Do you already have a pitch or brief?",
                helper: "This decides whether the next step should capture source text or a fresh summary."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    WizardChoiceCard(
                        title: "Yes, I have one",
                        summary: "Use the existing pitch or brief as the starting point for the project.",
                        isSelected: draft.hasPitch == true
                    ) {
                        draft.hasPitch = true
                    }

                    WizardChoiceCard(
                        title: "No, not yet",
                        summary: "Write a short project summary instead.",
                        isSelected: draft.hasPitch == false
                    ) {
                        draft.hasPitch = false
                    }
                }
            }
        case .pitch:
            promptLayout(
                question: "Paste the pitch or brief",
                helper: "You can also leave this empty and continue to a summary instead."
            ) {
                TextEditor(text: binding(\.pitchText))
                    .frame(minHeight: 180)
                    .font(.system(.body, design: .rounded))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border))
            }
        case .summary:
            promptLayout(
                question: "What is this project about?",
                helper: "Describe it in 2 to 4 sentences so the scaffold can seed the project README."
            ) {
                TextEditor(text: binding(\.summaryText))
                    .frame(minHeight: 180)
                    .font(.system(.body, design: .rounded))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.border))
            }
        case .structure:
            promptLayout(
                question: structurePromptSet.stepQuestion,
                helper: structurePromptSet.stepHelper
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(structurePromptSet.prompts) { prompt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(prompt.title)
                                .font(.headline)
                                .foregroundStyle(AppPalette.title)
                            Text(prompt.helper)
                                .font(.caption)
                                .foregroundStyle(AppPalette.subtle)
                            TextField(prompt.placeholder, text: structureBinding(for: prompt.id))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
        case .sourceMaterial:
            promptLayout(
                question: "Do you want to add source material now?",
                helper: "Examples: papers, newspaper stories, interview transcripts, and notes."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ScaffoldSourceMaterialChoice.allCases, id: \.self) { choice in
                        WizardChoiceCard(
                            title: choice.label,
                            summary: choice.summary,
                            isSelected: draft.sourceMaterialChoice == choice
                        ) {
                            draft.sourceMaterialChoice = choice
                        }
                    }
                }
            }
        case .priority:
            promptLayout(
                question: "How urgent is this project?",
                helper: "Keep the signal coarse for now. A tighter deadline field can come later."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ScaffoldProjectPriority.allCases, id: \.self) { choice in
                        WizardChoiceCard(
                            title: choice.label,
                            summary: choice.summary,
                            isSelected: draft.priority == choice
                        ) {
                            draft.priority = choice
                        }
                    }
                }
            }
        case .review:
            reviewStep
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm the essentials, then create the project with the existing scaffold workflow.")
                .foregroundStyle(AppPalette.subtle)

            MetadataGrid(rows: [
                ("Title", draft.trimmedTitle),
                ("Project kind", draft.projectKindLabel),
                ("Summary source", summarySourceLabel),
                ("Starter structure", starterStructureLabel),
                ("Source material", draft.sourceMaterialChoice?.label ?? "Not set"),
                ("Priority", draft.priority.label),
                ("Create at", draft.derivedProjectRoot(workspaceRoot: store.workspaceRoot))
            ])

            DisclosureGroup("Advanced details") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Folder name", text: binding(\.folderNameOverride))
                        .textFieldStyle(.roundedBorder)
                    TextField("Project root", text: binding(\.projectRootOverride))
                        .textFieldStyle(.roundedBorder)
                    TextField("Topics", text: binding(\.topics))
                        .textFieldStyle(.roundedBorder)
                    TextField("Entities", text: binding(\.entities))
                        .textFieldStyle(.roundedBorder)
                    Text("Topics and entities stay optional. Project kind is now written into the scaffolded README frontmatter.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.subtle)
                }
                .padding(.top, 8)
            }

            SectionCard(title: "README preview") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This excerpt shows the starter structure that will be written for this project type.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.subtle)

                    VStack(alignment: .leading, spacing: 18) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                readmePill("README.md")
                                readmePill(draft.projectKindLabel)
                                readmePill("status: active")
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                readmePill("README.md")
                                HStack(spacing: 8) {
                                    readmePill(draft.projectKindLabel)
                                    readmePill("status: active")
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(draft.trimmedTitle)
                                .font(.system(size: 28, weight: .semibold, design: .serif))
                                .foregroundStyle(AppPalette.title)
                            Text(readmePreviewSummary)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(readmePreviewSectionsData) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.title)
                                        .font(.headline)
                                        .foregroundStyle(AppPalette.title)
                                    ForEach(section.bullets, id: \.self) { bullet in
                                        Text("• \(bullet)")
                                            .foregroundStyle(AppPalette.subtle)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .textSelection(.enabled)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppPalette.border)
                    )

                    DisclosureGroup("Raw markdown excerpt") {
                        Text(readmePreview)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .foregroundStyle(AppPalette.subtle)
                }
            }

            SectionCard(title: "Preflight") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        WorkflowStatusBadge(status: preflightReport.status)
                        Text(preflightReport.summary)
                            .foregroundStyle(AppPalette.subtle)
                    }

                    if !preflightReport.missingItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Missing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppPalette.title)
                            ForEach(preflightReport.missingItems, id: \.self) { item in
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.subtle)
                            }
                        }
                    }

                    if let setupHint = preflightReport.setupHint, !setupHint.isEmpty {
                        Text(setupHint)
                            .font(.caption)
                            .foregroundStyle(AppPalette.subtle)
                    }
                }
            }

            SectionCard(title: "Command preview") {
                Text(commandPreview)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if draft.sourceMaterialChoice == .now {
                Text("After creation, the app will immediately prompt you to add files or folders into this project's `docs/` folder.")
                    .font(.caption)
                    .foregroundStyle(AppPalette.subtle)
            }
        }
    }

    private var summarySourceLabel: String {
        if !draft.trimmedSummary.isEmpty {
            return draft.hasPitch == true ? "Pitch plus short summary" : "Short summary"
        }
        if !draft.trimmedPitch.isEmpty {
            return "Pitch or brief"
        }
        return "Missing"
    }

    private var starterStructureLabel: String {
        if !draft.requiresSummaryStructuring {
            return "Derived from pitch"
        }
        return draft.hasCompletedSummaryStructuring ? "Explicit first structure" : "Missing"
    }

    private var readmePreview: String {
        let summary = readmePreviewSummary
        let previewSections = readmePreviewSectionsData
            .map { section in
                (["## \(section.title)"] + section.bullets.map { "- \($0)" }).joined(separator: "\n")
            }
            .joined(separator: "\n\n")

        return [
            "---",
            "project: \(draft.trimmedTitle)",
            "project_type: \(draft.mappedProjectType)",
            "deliverable: \(summary)",
            "---",
            "",
            "# \(draft.trimmedTitle)",
            "",
            summary,
            "",
            previewSections
        ].joined(separator: "\n")
    }

    private var readmePreviewSummary: String {
        draft.deliverableText.isEmpty ? "Short project summary." : draft.deliverableText
    }

    private var readmePreviewSectionsData: [ReadmePreviewSection] {
        readmePreviewSections(
            for: draft.mappedProjectType,
            structuredAnswers: [
                draft.trimmedStructureAnswerOne,
                draft.trimmedStructureAnswerTwo,
                draft.trimmedStructureAnswerThree
            ]
        )
    }

    private func promptLayout<Content: View>(
        question: String,
        helper: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(question)
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.title)
                Text(helper)
                    .foregroundStyle(AppPalette.subtle)
            }
            content()
        }
    }

    private func primaryActionDisabled(for step: ScaffoldProjectWizardStep) -> Bool {
        switch step {
        case .workingTitle:
            return draft.trimmedTitle.isEmpty || !draft.hasUsableDerivedFolderName
        case .projectKind:
            return false
        case .startingPoint:
            return draft.hasPitch == nil
        case .pitch:
            return false
        case .summary:
            return draft.trimmedSummary.isEmpty
        case .structure:
            return draft.requiresSummaryStructuring && !draft.hasCompletedSummaryStructuring
        case .sourceMaterial:
            return draft.sourceMaterialChoice == nil
        case .priority:
            return false
        case .review:
            return store.isRunning || !preflightReport.isRunnable
        }
    }

    private func moveForward() {
        store.scaffoldProjectWizardDraft.syncAdvancedDefaults(workspaceRoot: store.workspaceRoot)
        switch currentWizardStep {
        case .workingTitle:
            store.scaffoldProjectWizardStep = .projectKind
        case .projectKind:
            store.scaffoldProjectWizardStep = .startingPoint
        case .startingPoint:
            store.scaffoldProjectWizardStep = draft.hasPitch == true ? .pitch : .summary
        case .pitch:
            store.scaffoldProjectWizardStep = draft.trimmedPitch.isEmpty ? .summary : .sourceMaterial
        case .summary:
            store.scaffoldProjectWizardStep = draft.requiresSummaryStructuring ? .structure : .sourceMaterial
        case .structure:
            store.scaffoldProjectWizardStep = .sourceMaterial
        case .sourceMaterial:
            store.scaffoldProjectWizardStep = .priority
        case .priority:
            store.scaffoldProjectWizardStep = .review
        case .review:
            break
        }
    }

    private func moveBackward() {
        switch currentWizardStep {
        case .workingTitle:
            break
        case .projectKind:
            store.scaffoldProjectWizardStep = .workingTitle
        case .startingPoint:
            store.scaffoldProjectWizardStep = .projectKind
        case .pitch:
            store.scaffoldProjectWizardStep = .startingPoint
        case .summary:
            store.scaffoldProjectWizardStep = draft.hasPitch == true ? .pitch : .startingPoint
        case .structure:
            store.scaffoldProjectWizardStep = .summary
        case .sourceMaterial:
            if currentWizardStep == .sourceMaterial && draft.requiresSummaryStructuring {
                store.scaffoldProjectWizardStep = .structure
            } else if draft.hasPitch == true && draft.trimmedPitch.isEmpty {
                store.scaffoldProjectWizardStep = .summary
            } else if draft.hasPitch == true {
                store.scaffoldProjectWizardStep = .pitch
            } else {
                store.scaffoldProjectWizardStep = .summary
            }
        case .priority:
            store.scaffoldProjectWizardStep = .sourceMaterial
        case .review:
            store.scaffoldProjectWizardStep = .priority
        }
    }

    private func createProject() {
        let projectRoot = mappedState.stringValue(for: "project_root").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectRoot.isEmpty else { return }

        let projectURL = URL(fileURLWithPath: projectRoot)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDirectory) {
            let isReusableProject = isDirectory.boolValue && FileManager.default.fileExists(
                atPath: projectURL.appendingPathComponent("README.md").path
            )
            existingPathConflict = ExistingPathConflict(
                path: projectURL.path,
                kind: isReusableProject ? .reuseProject : .existingFolder
            )
            return
        }

        store.runWorkflow(workflow, with: mappedState)
    }

    private func binding(_ keyPath: WritableKeyPath<ScaffoldProjectWizardDraft, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                var updated = draft
                if keyPath == \.workingTitle {
                    updated.updateWorkingTitle(newValue, workspaceRoot: store.workspaceRoot)
                } else if keyPath == \.folderNameOverride {
                    updated.updateFolderNameOverride(newValue, workspaceRoot: store.workspaceRoot)
                } else {
                    updated[keyPath: keyPath] = newValue
                }
                draft = updated
            }
        )
    }

    private func structureBinding(for promptID: String) -> Binding<String> {
        switch promptID {
        case "one":
            return binding(\.structureAnswerOne)
        case "two":
            return binding(\.structureAnswerTwo)
        default:
            return binding(\.structureAnswerThree)
        }
    }

    private var structurePromptSet: ScaffoldStructurePromptSet {
        scaffoldStructurePromptSet(for: draft.mappedProjectType)
    }

    private func focusCurrentStep() {
        guard store.scaffoldProjectWizardStep == .workingTitle else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            focusedField = .workingTitle
        }
    }
}

private struct ExistingPathConflict: Identifiable {
    enum Kind {
        case reuseProject
        case existingFolder
    }

    let path: String
    let kind: Kind

    var id: String {
        "\(kindIdentifier)-\(path)"
    }

    private var kindIdentifier: String {
        switch kind {
        case .reuseProject:
            return "reuse"
        case .existingFolder:
            return "folder"
        }
    }
}

private struct WizardChoiceCard: View {
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
                        .foregroundStyle(AppPalette.title)
                    Text(summary)
                        .foregroundStyle(AppPalette.subtle)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AppPalette.title : AppPalette.subtle)
            }
            .padding(18)
            .background(AppPalette.card.opacity(isSelected ? 1.0 : 0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? AppPalette.title : AppPalette.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private func normalizedProjectSlug(_ text: String) -> String {
    let normalized = text
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()

    var pieces: [String] = []
    var current = ""

    for scalar in normalized.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            current.unicodeScalars.append(scalar)
        } else if !current.isEmpty {
            pieces.append(current)
            current.removeAll(keepingCapacity: true)
        }
    }

    if !current.isEmpty {
        pieces.append(current)
    }

    return pieces.joined(separator: "_")
}

private func currentProjectDate() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: .now)
}

private func currentProjectYear() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy"
    return formatter.string(from: .now)
}

private func defaultProjectOwner(existingValue: String?) -> String {
    let trimmedExisting = existingValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedExisting.isEmpty {
        return trimmedExisting
    }
    let systemName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
    return systemName.isEmpty ? "Workspace owner" : systemName
}

private func readmePreviewSections(for projectType: String, structuredAnswers: [String]) -> [ReadmePreviewSection] {
    let prompts = scaffoldStructurePromptSet(for: projectType).prompts
    let firstSectionBullets = zip(prompts, structuredAnswers).map { prompt, answer in
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? prompt.readmeLabel : "\(prompt.readmeLabel) \(trimmed)"
    }

    switch projectType {
    case "journalism":
        return [
            .init(
                title: "Reporting question",
                bullets: firstSectionBullets
            ),
            .init(
                title: "Source status",
                bullets: [
                    "Key documents:",
                    "Interviews:",
                    "Known gaps:"
                ]
            )
        ]
    case "data_journalism":
        return [
            .init(
                title: "Core question",
                bullets: firstSectionBullets
            ),
            .init(
                title: "Data plan",
                bullets: [
                    "Primary datasets:",
                    "Join keys or units of analysis:",
                    "Cleaning or transformation needs:"
                ]
            )
        ]
    case "tooling":
        return [
            .init(
                title: "Problem",
                bullets: firstSectionBullets
            ),
            .init(
                title: "Technical shape",
                bullets: [
                    "Inputs and outputs:",
                    "Runtime or stack:",
                    "Dependencies or integrations:"
                ]
            )
        ]
    default:
        return [
            .init(
                title: "Scope",
                bullets: firstSectionBullets
            ),
            .init(
                title: "Current context",
                bullets: [
                    "Relevant inputs:",
                    "Open questions:",
                    "Risks or unknowns:"
                ]
            )
        ]
    }
}

private func scaffoldStructurePromptSet(for projectType: String) -> ScaffoldStructurePromptSet {
    switch projectType {
    case "journalism":
        return ScaffoldStructurePromptSet(
            stepQuestion: "Turn the short summary into a first reporting structure",
            stepHelper: "Write the first reporting question, working hypothesis, and why this matters now. These answers stay editable and seed the README explicitly.",
            prompts: [
                .init(id: "one", title: "Main reporting question", placeholder: "What are you trying to find out?", helper: "Use one clear newsroom question.", readmeLabel: "Main reporting question:"),
                .init(id: "two", title: "Working hypothesis", placeholder: "What do you currently suspect or expect?", helper: "This can be tentative.", readmeLabel: "Working hypothesis:"),
                .init(id: "three", title: "Why this matters now", placeholder: "Why is this worth doing now?", helper: "Capture urgency, relevance, or public value.", readmeLabel: "Why this matters now:")
            ]
        )
    case "data_journalism":
        return ScaffoldStructurePromptSet(
            stepQuestion: "Turn the short summary into a first analysis structure",
            stepHelper: "Write the main question, the pattern or claim you expect, and why data is necessary here.",
            prompts: [
                .init(id: "one", title: "Main question", placeholder: "What should the data help answer?", helper: "Use one clear reporting or analytical question.", readmeLabel: "Main question:"),
                .init(id: "two", title: "Expected pattern or claim", placeholder: "What pattern, gap, or claim do you expect to test?", helper: "This can still be provisional.", readmeLabel: "Expected pattern or claim:"),
                .init(id: "three", title: "Why data is needed here", placeholder: "Why can’t this be answered well without data?", helper: "Anchor the role of the analysis explicitly.", readmeLabel: "Why data is needed here:")
            ]
        )
    case "tooling":
        return ScaffoldStructurePromptSet(
            stepQuestion: "Turn the short summary into a first build structure",
            stepHelper: "Clarify the main problem, who the tool is for, and the main constraint or non-goal before the scaffold becomes canonical.",
            prompts: [
                .init(id: "one", title: "What this should unblock", placeholder: "What should this tool make easier or possible?", helper: "Name the main problem it should solve.", readmeLabel: "What this tool should unblock:"),
                .init(id: "two", title: "Who it is for", placeholder: "Who is the primary user?", helper: "It can still be just you.", readmeLabel: "Who it is for:"),
                .init(id: "three", title: "Constraint or non-goal", placeholder: "What should this not turn into?", helper: "Keep scope and constraints visible early.", readmeLabel: "Constraints or non-goals:")
            ]
        )
    default:
        return ScaffoldStructurePromptSet(
            stepQuestion: "Turn the short summary into a first project structure",
            stepHelper: "Clarify what this project is, what it is not, and why it exists before the README is created.",
            prompts: [
                .init(id: "one", title: "What this project is", placeholder: "What is the project actually for?", helper: "Name the core scope plainly.", readmeLabel: "What this project is:"),
                .init(id: "two", title: "What it is not", placeholder: "What is outside scope right now?", helper: "A short boundary is enough.", readmeLabel: "What it is not:"),
                .init(id: "three", title: "Why it exists", placeholder: "Why is this worth capturing?", helper: "Make the purpose explicit.", readmeLabel: "Why it exists:")
            ]
        )
    }
}

private struct ReadmePreviewSection: Identifiable {
    let id = UUID()
    let title: String
    let bullets: [String]
}

private struct ScaffoldStructurePromptSet {
    let stepQuestion: String
    let stepHelper: String
    let prompts: [ScaffoldStructurePrompt]
}

private struct ScaffoldStructurePrompt: Identifiable {
    let id: String
    let title: String
    let placeholder: String
    let helper: String
    let readmeLabel: String
}

private struct ReadmePreviewPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppPalette.card.opacity(0.98), in: Capsule())
            .overlay(Capsule().stroke(AppPalette.border))
            .foregroundStyle(AppPalette.subtle)
    }
}

private func readmePill(_ text: String) -> some View {
    ReadmePreviewPill(text: text)
}
