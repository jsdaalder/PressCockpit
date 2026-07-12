import Foundation

struct WorkspaceQueryStore {
    let snapshot: WorkspaceSnapshot
    private let itemsByID: [String: WorkspaceItem]

    static let empty = WorkspaceQueryStore(snapshot: .empty)

    init(snapshot: WorkspaceSnapshot) {
        self.snapshot = snapshot
        self.itemsByID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
    }

    var items: [WorkspaceItem] {
        snapshot.items
    }

    var firstItem: WorkspaceItem? {
        snapshot.items.first
    }

    func item(id: String?) -> WorkspaceItem? {
        guard let id else { return nil }
        return itemsByID[id]
    }

    func filteredItems(matching rawQuery: String) -> [WorkspaceItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.title.lowercased().contains(query)
                || item.summary.lowercased().contains(query)
                || item.path.lowercased().contains(query)
                || item.tags.joined(separator: " ").lowercased().contains(query)
        }
    }
}
