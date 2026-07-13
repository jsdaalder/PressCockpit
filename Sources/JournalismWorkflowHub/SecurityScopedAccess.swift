import Foundation

enum SecurityScopedAccess {
    static func withAccess<T>(to urls: [URL], _ body: () throws -> T) throws -> T {
        let scopedURLs = deduplicated(urls)
        let accessedURLs = scopedURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in accessedURLs.reversed() {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try body()
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            return seen.insert(key).inserted
        }
    }
}
