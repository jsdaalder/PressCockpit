import Foundation

struct PublicationStore {
    let workspaceRoot: URL

    var publicationTrackerURL: URL {
        workspaceRoot.appendingPathComponent("Resources/knowledge_ops/index/publication_tracker.csv")
    }

    var projectCoverageURL: URL {
        workspaceRoot.appendingPathComponent("Resources/knowledge_ops/index/project_publication_coverage.csv")
    }

    func load() -> PublicationSnapshot {
        let stories = loadTracker()
        let projects = loadProjectCoverage()

        let storiesByYear = Dictionary(grouping: stories, by: { $0.year })
        let projectsByYear = Dictionary(grouping: projects, by: { $0.year })
        let matchedCount = stories.filter { $0.matchStatus == "matched" }.count
        let missingCount = projects.filter { $0.publishedStatus != "published" }.count

        return PublicationSnapshot(
            storiesByYear: storiesByYear,
            projectsByYear: projectsByYear,
            matchedCount: matchedCount,
            missingCount: missingCount
        )
    }

    private func loadTracker() -> [PublicationStory] {
        let rows = readCSV(publicationTrackerURL)
        return rows.compactMap { row in
            guard let pdfTitle = row["pdf_title"], !pdfTitle.isEmpty else { return nil }
            let year = row["published_year"] ?? ""
            let pdfPath = row["pdf_path"] ?? ""
            let projectTitle = row["matched_project_title"] ?? ""
            let projectPath = row["matched_project_path"] ?? ""
            let projectReadmePath = row["matched_project_readme"] ?? ""
            let matchStatus = row["match_status"] ?? ""
            let matchBasis = row["match_basis"] ?? ""
            let reviewDecision = row["review_decision"] ?? ""
            let reviewNotes = row["review_notes"] ?? ""

            return PublicationStory(
                id: "\(year)|\(pdfTitle)",
                year: year,
                pdfTitle: pdfTitle,
                pdfPath: pdfPath,
                projectTitle: projectTitle,
                projectPath: projectPath,
                projectReadmePath: projectReadmePath,
                matchStatus: matchStatus,
                matchBasis: matchBasis,
                reviewDecision: reviewDecision,
                reviewNotes: reviewNotes
            )
        }
    }

    private func loadProjectCoverage() -> [PublicationProject] {
        let rows = readCSV(projectCoverageURL)
        return rows.compactMap { row in
            guard let slug = row["project_slug"], !slug.isEmpty else { return nil }
            let year = row["project_year"] ?? ""
            let path = row["project_path"] ?? ""
            let readmePath = row["readme_path"] ?? ""
            let title = row["readme_title"] ?? slug
            let quality = row["readme_quality"] ?? ""
            let count = Int(row["matched_pdf_count"] ?? "") ?? 0
            let titles = (row["matched_pdf_titles"] ?? "")
                .split(separator: "|")
                .map { String($0) }
                .filter { !$0.isEmpty }
            let status = row["published_status_from_pdfs"] ?? ""
            return PublicationProject(
                id: "\(year)|\(slug)",
                year: year,
                slug: slug,
                path: path,
                readmePath: readmePath,
                title: title,
                quality: quality,
                matchedPdfCount: count,
                matchedPdfTitles: titles,
                publishedStatus: status
            )
        }
    }

    private func readCSV(_ url: URL) -> [[String: String]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else { return [] }
        let headers = parseCSVLine(headerLine)
        guard !headers.isEmpty else { return [] }

        return lines.dropFirst().compactMap { line in
            let values = parseCSVLine(line)
            guard !values.isEmpty else { return nil }
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() where index < values.count {
                row[header] = values[index]
            }
            return row
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if inQuotes && index + 1 < characters.count && characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if character == "," && !inQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }

        values.append(current)
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

