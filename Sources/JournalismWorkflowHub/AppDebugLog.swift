import Foundation

enum AppDebugLog {
    static func write(
        _ message: String,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = .now
    ) {
        let line = "[\(timestamp(now))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let logURL = journalismWorkflowHubLogsDirectory(
            supportDirectory: supportDirectory,
            fileManager: fileManager
        ).appendingPathComponent("app.log")

        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Debug logging should never break the app.
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
