import Foundation

struct PlanningStore {
    let workspaceRoot: URL

    func load() -> PlanningSnapshot {
        let projectRoot = planningProjectRoot()
        let docs = loadDocuments(from: projectRoot)
        let title = loadProjectTitle(from: projectRoot)
        return PlanningSnapshot(
            projectPath: projectRoot.path,
            projectTitle: title,
            docs: docs
        )
    }

    private func planningProjectRoot() -> URL {
        workspaceRoot
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("journalism_workflow_hub_plan", isDirectory: true)
    }

    private func loadDocuments(from projectRoot: URL) -> [PlanningDocument] {
        let docsDirectory = projectRoot.appendingPathComponent("docs", isDirectory: true)
        let orderedFiles = [
            "roadmap.md",
            "backlog.md",
            "architecture.md",
            "automation_ideas.md",
            "current_priorities.md"
        ]

        return orderedFiles.compactMap { fileName in
            let url = docsDirectory.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let fallbackTitle = humanizeSlug(url.deletingPathExtension().lastPathComponent)
            let title = extractMarkdownTitle(from: body, fallback: fallbackTitle)
            let summary = extractMarkdownSummary(from: body)
            return PlanningDocument(
                id: url.path,
                title: title,
                path: url.path,
                summary: summary,
                body: body
            )
        }
    }

    private func loadProjectTitle(from projectRoot: URL) -> String {
        let readmeURL = projectRoot.appendingPathComponent("README.md")
        guard let text = try? String(contentsOf: readmeURL, encoding: .utf8) else {
            return "Journalism Workflow Hub Plan"
        }

        let fallbackTitle = "Journalism Workflow Hub Plan"
        return extractMarkdownTitle(from: text, fallback: fallbackTitle)
    }
}

private func extractMarkdownTitle(from text: String, fallback: String) -> String {
    for line in stripFrontmatter(from: text).components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("# ") {
            return String(trimmed.dropFirst(2))
        }
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return fallback
}

private func extractMarkdownSummary(from text: String) -> String {
    var sawHeading = false
    for line in stripFrontmatter(from: text).components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            continue
        }
        if trimmed.hasPrefix("# ") {
            sawHeading = true
            continue
        }
        if !sawHeading {
            continue
        }
        if trimmed.hasPrefix("-") || trimmed.hasPrefix(">") {
            continue
        }
        if trimmed.count >= 16 {
            return trimmed
        }
    }
    return ""
}

private func stripFrontmatter(from text: String) -> String {
    guard text.hasPrefix("---\n") else { return text }
    let lines = text.components(separatedBy: .newlines)
    var endIndex: Int?
    for index in 1..<lines.count {
        if lines[index].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
            endIndex = index
            break
        }
    }
    guard let endIndex else { return text }
    return lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}
