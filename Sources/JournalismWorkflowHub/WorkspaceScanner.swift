import Foundation

struct WorkspaceScanner {
    let workspaceRoot: URL

    private let ignoredDirectories: Set<String> = [
        ".git",
        ".build",
        ".swiftpm",
        ".venv",
        ".pytest_cache",
        "__pycache__",
        "node_modules",
        ".next",
        "dist",
        "build",
        ".DS_Store"
    ]

    private let readableExtensions: Set<String> = [
        "md", "gdoc", "pdf", "csv", "json", "jsonl", "txt", "xlsx", "xls", "py", "command", "html", "ics"
    ]

    func scan() -> WorkspaceSnapshot {
        let items = discoverItems()
        let publication = PublicationStore(workspaceRoot: workspaceRoot).load()
        return WorkspaceSnapshot(scannedAt: .now, items: items, publication: publication)
    }

    private func discoverItems() -> [WorkspaceItem] {
        let fm = FileManager.default
        let roots: [(WorkspaceSection, URL)] = [
            (.projects, workspaceRoot.appendingPathComponent("Projects")),
            (.areas, workspaceRoot.appendingPathComponent("Areas")),
            (.resources, workspaceRoot.appendingPathComponent("Resources")),
            (.archives, workspaceRoot.appendingPathComponent("Archives"))
        ]

        var items: [WorkspaceItem] = []
        for (section, root) in roots where fm.fileExists(atPath: root.path) {
            items.append(contentsOf: discoverItems(in: root, section: section, depth: 0))
        }

        return items.sorted {
            if $0.section.rawValue != $1.section.rawValue {
                return $0.section.rawValue < $1.section.rawValue
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func discoverItems(in directory: URL, section: WorkspaceSection, depth: Int) -> [WorkspaceItem] {
        let fm = FileManager.default
        guard depth <= 6 else { return [] }

        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [WorkspaceItem] = []
        if let item = makeItem(for: directory, section: section) {
            items.append(item)
        }

        for child in children {
            if shouldIgnore(child) {
                continue
            }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            items.append(contentsOf: discoverItems(in: child, section: section, depth: depth + 1))
        }

        return items
    }

    private func shouldIgnore(_ url: URL) -> Bool {
        ignoredDirectories.contains(url.lastPathComponent)
    }

    private func makeItem(for directory: URL, section: WorkspaceSection) -> WorkspaceItem? {
        let fm = FileManager.default
        let readmeURL = directory.appendingPathComponent("README.md")
        guard fm.fileExists(atPath: readmeURL.path) else {
            return nil
        }
        let agentsURL = directory.appendingPathComponent("AGENTS.md")

        let readmeText = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
        let agentsText = (try? String(contentsOf: agentsURL, encoding: .utf8)) ?? ""
        let (frontmatter, body) = parseFrontmatter(readmeText)
        let title = extractTitle(from: frontmatter, body: body, fallback: directory.lastPathComponent)
        let summary = extractSummary(from: body)
        let agentsSummary = extractAgentsSummary(from: agentsText)
        let projectType = classifyProjectType(
            section: section,
            directory: directory,
            frontmatter: frontmatter,
            readmeBody: body,
            agentsText: agentsText
        )
        let lifecycleStage = inferLifecycleStage(section: section, frontmatter: frontmatter, readmeBody: body)
        let safetyPosture = inferSafetyPosture(
            section: section,
            projectType: projectType,
            directory: directory,
            readmeBody: body,
            agentsText: agentsText
        )
        let counts = countDirectChildren(at: directory)

        return WorkspaceItem(
            id: directory.path,
            section: section,
            path: directory.path,
            readmePath: readmeURL.path,
            agentsPath: fm.fileExists(atPath: agentsURL.path) ? agentsURL.path : nil,
            title: title,
            summary: summary,
            agentsSummary: agentsSummary,
            frontmatter: frontmatter,
            projectType: projectType,
            lifecycleStage: lifecycleStage,
            safetyPosture: safetyPosture,
            directFileCount: counts.fileCount,
            directFolderCount: counts.folderCount,
            markdownFiles: counts.markdownCount,
            pdfFiles: counts.pdfCount,
            gdocFiles: counts.gdocCount,
            csvFiles: counts.csvCount,
            xlsxFiles: counts.xlsxCount
        )
    }

    private func countDirectChildren(at directory: URL) -> (
        fileCount: Int,
        folderCount: Int,
        markdownCount: Int,
        pdfCount: Int,
        gdocCount: Int,
        csvCount: Int,
        xlsxCount: Int
    ) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, 0, 0, 0, 0, 0)
        }

        var fileCount = 0
        var folderCount = 0
        var markdownCount = 0
        var pdfCount = 0
        var gdocCount = 0
        var csvCount = 0
        var xlsxCount = 0

        for child in children {
            if shouldIgnore(child) {
                continue
            }
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: child.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                folderCount += 1
                continue
            }
            fileCount += 1
            switch child.pathExtension.lowercased() {
            case "md":
                markdownCount += 1
            case "pdf":
                pdfCount += 1
            case "gdoc":
                gdocCount += 1
            case "csv":
                csvCount += 1
            case "xlsx", "xls":
                xlsxCount += 1
            default:
                break
            }
        }

        return (fileCount, folderCount, markdownCount, pdfCount, gdocCount, csvCount, xlsxCount)
    }

    private func parseFrontmatter(_ text: String) -> ([String: String], String) {
        guard text.hasPrefix("---\n") else { return ([:], text) }
        let lines = text.components(separatedBy: .newlines)
        var frontmatter: [String: String] = [:]
        var endIndex: Int?

        for index in 1..<lines.count {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                endIndex = index
                break
            }
            guard let colon = lines[index].firstIndex(of: ":") else { continue }
            let key = lines[index][..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[index][lines[index].index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            frontmatter[key] = value
        }

        guard let endIndex else { return ([:], text) }
        let body = lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (frontmatter, body)
    }

    private func extractTitle(from frontmatter: [String: String], body: String, fallback: String) -> String {
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
            if !trimmed.isEmpty, !trimmed.hasPrefix("-"), !trimmed.hasPrefix(">") {
                return trimmed
            }
        }

        if let project = frontmatter["project"], !project.isEmpty {
            return project
        }

        return humanizeSlug(fallback)
    }

    private func extractSummary(from body: String) -> String {
        var skippedHeading = false
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "---" {
                continue
            }
            if trimmed.hasPrefix("# ") {
                skippedHeading = true
                continue
            }
            if !skippedHeading {
                continue
            }
            if trimmed.hasPrefix("-") || trimmed.hasPrefix(">") {
                continue
            }
            if trimmed.count >= 24 {
                return trimmed
            }
        }
        return ""
    }

    private func extractAgentsSummary(from text: String) -> String {
        guard !text.isEmpty else { return "" }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "---" || trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.hasPrefix("-") {
                continue
            }
            if trimmed.count >= 20 {
                return trimmed
            }
        }
        return ""
    }

    private func classifyProjectType(
        section: WorkspaceSection,
        directory: URL,
        frontmatter: [String: String],
        readmeBody: String,
        agentsText: String
    ) -> WorkspaceProjectType {
        switch section {
        case .areas:
            return .area
        case .resources:
            return .resource
        case .archives:
            return .archive
        case .projects:
            break
        }

        let corpus = ([directory.lastPathComponent] + frontmatter.values + [readmeBody, agentsText])
            .joined(separator: "\n")
            .lowercased()

        if corpus.contains("data-journalism") || corpus.contains("data journalism") {
            return .dataJournalism
        }

        if corpus.contains("tooling or personal projects")
            || corpus.contains("tooling project")
            || corpus.contains("prototype")
            || corpus.contains("swiftui")
            || corpus.contains("launcher")
            || corpus.contains("cli")
            || corpus.contains("automation")
            || corpus.contains("app code")
            || corpus.contains("macos app")
            || corpus.contains("event-scanner") {
            return .tooling
        }

        if corpus.contains("journalism project")
            || corpus.contains("reporting workspace")
            || frontmatter["deliverable"]?.isEmpty == false
            || frontmatter["type"] == "project" {
            return .journalism
        }

        return .general
    }

    private func inferLifecycleStage(
        section: WorkspaceSection,
        frontmatter: [String: String],
        readmeBody: String
    ) -> String {
        if let status = frontmatter["status"], !status.isEmpty {
            return humanizeStatus(status)
        }

        switch section {
        case .archives:
            return "Archived"
        case .areas:
            return "Ongoing"
        case .resources:
            return "Reusable"
        case .projects:
            let lowered = readmeBody.lowercased()
            if lowered.contains("roadmap") || lowered.contains("backlog") {
                return "Planning"
            }
            return "Active"
        }
    }

    private func inferSafetyPosture(
        section: WorkspaceSection,
        projectType: WorkspaceProjectType,
        directory: URL,
        readmeBody: String,
        agentsText: String
    ) -> WorkspaceSafetyPosture {
        if section == .archives {
            return .archival
        }

        let corpus = [directory.lastPathComponent, readmeBody, agentsText]
            .joined(separator: "\n")
            .lowercased()

        if corpus.contains("privacy-sensitive")
            || corpus.contains("privacy sensitive")
            || corpus.contains("local-first")
            || corpus.contains("local only")
            || corpus.contains("publishability")
            || corpus.contains("personal exports")
            || corpus.contains("redaction") {
            return .localSensitive
        }

        switch projectType {
        case .tooling, .resource, .area, .general:
            return .internalOnly
        case .archive:
            return .archival
        case .journalism, .dataJournalism:
            return .publishable
        }
    }
}

private func humanizeSlug(_ slug: String) -> String {
    slug
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { String($0).capitalized }
        .joined(separator: " ")
}

private func humanizeStatus(_ status: String) -> String {
    status
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { token in
            token.lowercased() == "qa" ? "QA" : token.capitalized
        }
        .joined(separator: " ")
}
