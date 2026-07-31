import Foundation

enum OverviewTarget: Hashable {
    case overview
    case workspace(String)
    case workflow(String)
    case publication
    case run(String)
}

struct OverviewProjectSummary: Identifiable, Hashable {
    let item: WorkspaceItem
    let flags: [String]
    let displayFlags: [String]
    let stateBadgeText: String
    let nextStep: String
    let primaryDocuments: [WorkspaceDocument]
    let primaryTarget: OverviewTarget
    let primaryButtonTitle: String

    var id: String { item.id }
    var primaryFlag: String? { flags.first }
    var displayPrimaryFlag: String? { stateBadgeText }
}

struct OverviewActionSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let buttonTitle: String
    let count: Int
    let target: OverviewTarget
}

struct OverviewOperationSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let buttonTitle: String
    let count: Int
    let target: OverviewTarget
}

struct OverviewOpenProjectGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [OverviewProjectSummary]
}

enum OverviewDeriver {
    static func activeReportingProjects(from snapshot: WorkspaceSnapshot) -> [WorkspaceItem] {
        snapshot.items
            .filter {
                $0.section == .projects
                    && $0.isProjectRoot
                    && isReportingProjectType($0.projectType)
                    && $0.activityState == .active
            }
    }

    static func openProjectGroups(from snapshot: WorkspaceSnapshot, runs: [WorkflowRun]) -> [OverviewOpenProjectGroup] {
        let grouped = Dictionary(grouping: snapshot.items.filter(shouldIncludeInOpenProjectList)) { item in
            item.workflowStage
        }

        return grouped
            .map { workflowStage, items in
                OverviewOpenProjectGroup(
                    id: workflowStage?.rawValue ?? "unstaged",
                    title: workflowStage?.label ?? "Unstaged",
                    items: items
                        .sorted(by: compareOpenProjectListItems)
                        .map { summary(for: $0, runs: runs) }
                )
            }
            .sorted(by: compareOpenProjectGroups)
    }

    static func projectSummaries(from snapshot: WorkspaceSnapshot, runs: [WorkflowRun]) -> [OverviewProjectSummary] {
        activeReportingProjects(from: snapshot)
            .filter(\.isInDailyFocus)
            .sorted { compareProjects($0, $1, runs: runs) }
            .map { summary(for: $0, runs: runs) }
    }

    static func suggestedActions(from snapshot: WorkspaceSnapshot, runs: [WorkflowRun]) -> [OverviewActionSummary] {
        let activeProjects = activeReportingProjects(from: snapshot)
        let reviewProjects = activeProjects.filter(needsSharingReview)
        let basicsProjects = activeProjects.filter(hasProjectBasicsGap)

        return [
            OverviewActionSummary(
                id: "review",
                title: "Needs review before sharing",
                body: reviewProjects.isEmpty
                    ? "No active reporting projects currently need a sharing review."
                    : "\(reviewProjects.count) active \(pluralized("project", count: reviewProjects.count)) still need review before sharing or export.",
                buttonTitle: reviewProjects.isEmpty ? "View" : "Open project",
                count: reviewProjects.count,
                target: reviewProjects.first.map { .workspace($0.id) } ?? activeProjects.first.map { .workspace($0.id) } ?? .overview
            ),
            OverviewActionSummary(
                id: "basics",
                title: "Project basics missing",
                body: basicsProjects.isEmpty
                    ? "Active reporting projects currently have the expected basics in place."
                    : "\(basicsProjects.count) active \(pluralized("project", count: basicsProjects.count)) still need clearer setup such as local rules, owner, or deliverable.",
                buttonTitle: basicsProjects.isEmpty ? "View" : "Open project",
                count: basicsProjects.count,
                target: basicsProjects.first.map { .workspace($0.id) } ?? activeProjects.first.map { .workspace($0.id) } ?? .overview
            )
        ].filter { $0.count > 0 || activeProjects.isEmpty == false }
    }

    static func operationSummaries(from snapshot: WorkspaceSnapshot, runs: [WorkflowRun]) -> [OverviewOperationSummary] {
        let activeProjects = activeReportingProjects(from: snapshot)
        let adminProjects = snapshot.items.filter { $0.section == .projects && $0.isProjectRoot && $0.agentsPath == nil }
        let stateMigrationProjects = snapshot.items.filter(needsProjectStateMigration)
        let failedRuns = latestFailedRunsByScope(from: runs)

        return [
            OverviewOperationSummary(
                id: "workflow-follow-up",
                title: "Failed workflow runs",
                detail: failedRuns.isEmpty
                    ? "No failed runs are waiting."
                    : "\(failedRuns.count) saved \(pluralized("run", count: failedRuns.count)) need review.",
                buttonTitle: failedRuns.isEmpty ? "View" : "Review run",
                count: failedRuns.count,
                target: failedRuns.first.map { .run($0.id) } ?? .overview
            ),
            OverviewOperationSummary(
                id: "metadata-cleanup",
                title: "Admin cleanup",
                detail: adminProjects.isEmpty
                    ? "No project roots are missing local rules."
                    : "\(adminProjects.count) project \(pluralized("root", count: adminProjects.count)) still need an `AGENTS.md` file.",
                buttonTitle: "Open project",
                count: adminProjects.count,
                target: adminProjects.first.map { .workspace($0.id) } ?? activeProjects.first.map { .workspace($0.id) } ?? .overview
            ),
            OverviewOperationSummary(
                id: "state-cleanup",
                title: "Project state cleanup",
                detail: stateMigrationProjects.isEmpty
                    ? "No projects are still relying on compatibility status fallback."
                    : "\(stateMigrationProjects.count) project \(pluralized("root", count: stateMigrationProjects.count)) still rely on compatibility status instead of explicit project-state fields.",
                buttonTitle: "Open project",
                count: stateMigrationProjects.count,
                target: stateMigrationProjects.first.map { .workspace($0.id) } ?? activeProjects.first.map { .workspace($0.id) } ?? .overview
            ),
            OverviewOperationSummary(
                id: "publication-review",
                title: "Publication follow-up",
                detail: snapshot.publication.missingCount == 0
                    ? "No publication mapping gaps are currently tracked."
                    : "\(snapshot.publication.missingCount) project \(pluralized("folder", count: snapshot.publication.missingCount)) still lack a linked PDF match.",
                buttonTitle: "Open index",
                count: snapshot.publication.missingCount,
                target: .publication
            )
        ]
    }

    private static func isReportingProjectType(_ type: WorkspaceProjectType) -> Bool {
        type == .journalism || type == .dataJournalism
    }

    private static func shouldIncludeInOpenProjectList(_ item: WorkspaceItem) -> Bool {
        guard item.section == .projects,
              item.isProjectRoot,
              isReportingProjectType(item.projectType),
              item.activityState == .active else {
            return false
        }

        return !item.isInDailyFocus
    }

    private static func compareOpenProjectGroups(_ lhs: OverviewOpenProjectGroup, _ rhs: OverviewOpenProjectGroup) -> Bool {
        let lhsStage = lhs.items.first?.item.workflowStage
        let rhsStage = rhs.items.first?.item.workflowStage
        let lhsPriority = workflowStagePriority(lhsStage)
        let rhsPriority = workflowStagePriority(rhsStage)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func compareOpenProjectListItems(_ lhs: WorkspaceItem, _ rhs: WorkspaceItem) -> Bool {
        let lhsActivityPriority = activityPriority(lhs.activityState)
        let rhsActivityPriority = activityPriority(rhs.activityState)
        if lhsActivityPriority != rhsActivityPriority {
            return lhsActivityPriority < rhsActivityPriority
        }

        let lhsInactivePriority = inactiveReasonPriority(lhs.inactiveReason)
        let rhsInactivePriority = inactiveReasonPriority(rhs.inactiveReason)
        if lhsInactivePriority != rhsInactivePriority {
            return lhsInactivePriority < rhsInactivePriority
        }

        let lhsDate = startedDate(for: lhs)
        let rhsDate = startedDate(for: rhs)
        if lhsDate != rhsDate {
            return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func compareProjects(_ lhs: WorkspaceItem, _ rhs: WorkspaceItem, runs: [WorkflowRun]) -> Bool {
        let lhsSeverity = severity(for: lhs, runs: runs)
        let rhsSeverity = severity(for: rhs, runs: runs)
        if lhsSeverity != rhsSeverity {
            return lhsSeverity < rhsSeverity
        }

        let lhsDate = startedDate(for: lhs)
        let rhsDate = startedDate(for: rhs)
        if lhsDate != rhsDate {
            return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func summary(for item: WorkspaceItem, runs: [WorkflowRun]) -> OverviewProjectSummary {
        let flags = projectFlags(for: item, runs: runs)
        return OverviewProjectSummary(
            item: item,
            flags: flags,
            displayFlags: displayFlags(from: flags),
            stateBadgeText: item.projectStateBadgeLabel,
            nextStep: nextStep(for: item, flags: flags),
            primaryDocuments: item.primaryDocuments,
            primaryTarget: .workspace(item.id),
            primaryButtonTitle: "Open in app"
        )
    }

    private static func projectFlags(for item: WorkspaceItem, runs: [WorkflowRun]) -> [String] {
        var flags: [String] = []

        if latestFailedRun(for: item, runs: runs) != nil {
            flags.append("Workflow needs attention")
        }

        if hasProjectBasicsGap(item) {
            flags.append("Project setup incomplete")
        }

        if needsSharingReview(item) {
            switch item.safetyPosture {
            case .unknown:
                flags.append("Needs review before sharing")
            case .localSensitive:
                flags.append("Local-only handling")
            default:
                break
            }
        }

        return flags
    }

    private static func nextStep(for item: WorkspaceItem, flags: [String]) -> String {
        if flags.contains("Workflow needs attention") {
            return "Open the project and check the latest workflow issue before continuing the reporting."
        }
        if flags.contains("Project setup incomplete") {
            return "Tighten the summary, started date, or deliverable so the project is easier to trust and act on."
        }
        if flags.contains("Needs review before sharing") || flags.contains("Local-only handling") {
            return "Review the safety and sharing posture before export or publication-oriented work."
        }
        if !item.summary.isEmpty {
            return "Open the project and continue the next reporting step."
        }
        return "Open the project README and sharpen the current reporting direction."
    }

    private static func displayFlags(from flags: [String]) -> [String] {
        flags.filter {
            $0 == "Needs review before sharing" || $0 == "Local-only handling"
        }
    }

    private static func needsSharingReview(_ item: WorkspaceItem) -> Bool {
        item.safetyPosture == .unknown || item.safetyPosture == .localSensitive
    }

    private static func hasProjectBasicsGap(_ item: WorkspaceItem) -> Bool {
        item.summary.isEmpty || hasMetadataGap(item)
    }

    private static func hasMetadataGap(_ item: WorkspaceItem) -> Bool {
        let started = item.frontmatter["started"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let deliverable = item.frontmatter["deliverable"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return started.isEmpty || deliverable.isEmpty
    }

    private static func needsProjectStateMigration(_ item: WorkspaceItem) -> Bool {
        item.section == .projects
            && item.isProjectRoot
            && item.projectState != nil
            && !item.hasExplicitProjectStateFrontmatter
    }

    private static func severity(for item: WorkspaceItem, runs: [WorkflowRun]) -> Int {
        if latestFailedRun(for: item, runs: runs) != nil {
            return 0
        }
        if hasProjectBasicsGap(item) {
            return 1
        }
        if needsSharingReview(item) {
            return 2
        }
        return 3
    }

    private static func workflowStagePriority(_ stage: ProjectWorkflowStage?) -> Int {
        guard let stage else { return Int.max }
        return ProjectWorkflowStage.allCases.firstIndex(of: stage) ?? Int.max
    }

    private static func activityPriority(_ state: ProjectActivityState?) -> Int {
        switch state {
        case .active:
            return 0
        case .inactive:
            return 1
        case nil:
            return 2
        }
    }

    private static func inactiveReasonPriority(_ reason: ProjectInactiveReason?) -> Int {
        switch reason {
        case .waiting:
            return 0
        case .parked:
            return 1
        case .discarded:
            return 2
        case .finished:
            return 3
        case nil:
            return 4
        }
    }

    private static func startedDate(for item: WorkspaceItem) -> Date? {
        guard let started = item.frontmatter["started"], !started.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: started)
    }

    private static func pluralized(_ noun: String, count: Int) -> String {
        count == 1 ? noun : noun + "s"
    }

    private static func latestFailedRun(for item: WorkspaceItem, runs: [WorkflowRun]) -> WorkflowRun? {
        latestFailedRunsByScope(from: runs)
            .first(where: { $0.selectionPath == item.path })
    }

    private static func latestFailedRunsByScope(from runs: [WorkflowRun]) -> [WorkflowRun] {
        var latestByScope: [String: WorkflowRun] = [:]

        for run in runs {
            let scope = run.selectionPath ?? run.workflowID
            if let existing = latestByScope[scope], existing.startedAt > run.startedAt {
                continue
            }
            latestByScope[scope] = run
        }

        return latestByScope.values
            .filter { $0.exitCode != 0 }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
