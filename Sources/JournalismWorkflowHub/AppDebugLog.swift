import Foundation

enum AppDebugLog {
    static let maximumFileSizeBytes = 256 * 1024

    static func record(
        _ message: String,
        enabled: Bool,
        supportDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = .now,
        maximumFileSizeBytes: Int = Self.maximumFileSizeBytes
    ) {
        guard enabled else { return }

        let normalizedMessage = normalize(message)
        guard !normalizedMessage.isEmpty else { return }

        let line = "[\(timestamp(now))] \(normalizedMessage)\n"
        guard let data = line.data(using: .utf8) else { return }

        let logURL = journalismWorkflowHubLogFileURL(
            supportDirectory: supportDirectory,
            fileManager: fileManager
        )

        rotateIfNeeded(
            logURL: logURL,
            incomingBytes: data.count,
            fileManager: fileManager,
            maximumFileSizeBytes: maximumFileSizeBytes
        )

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

    private static func rotateIfNeeded(
        logURL: URL,
        incomingBytes: Int,
        fileManager: FileManager,
        maximumFileSizeBytes: Int
    ) {
        guard maximumFileSizeBytes > 0,
              fileManager.fileExists(atPath: logURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return
        }

        let currentSize = sizeNumber.intValue
        guard currentSize + incomingBytes > maximumFileSizeBytes else {
            return
        }

        let previousLogURL = logURL.deletingLastPathComponent().appendingPathComponent("app.previous.log")

        do {
            if fileManager.fileExists(atPath: previousLogURL.path) {
                try fileManager.removeItem(at: previousLogURL)
            }
            try fileManager.moveItem(at: logURL, to: previousLogURL)
        } catch {
            try? fileManager.removeItem(at: logURL)
        }
    }

    private static func normalize(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
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
