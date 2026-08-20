import Foundation

struct WidgetLocalAction: Codable, Equatable {
    let id: String
    let sourceId: String
    let sourceName: String
    let relativePath: String
    let title: String
    let task: String
    let intent: String
    let detail: String?
    let savedAt: String
}

struct WidgetBoardState: Codable, Equatable {
    var done: [String] = []
    var tracked: [String] = []
    var burned: [String] = []
    var currentAction: String?
    var custom: [WidgetLocalAction] = []
}

struct WidgetAction: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let intent: String
    let task: String
    let detail: String?
    let savedDays: Int
    let sourceName: String
    let sourceType: String
    let hasSource: Bool
}

struct WidgetSnapshot: Codable {
    var state: WidgetBoardState
    let actions: [WidgetAction]
}

enum SavedToActionWidgetStore {
    static let stateKey = "saved-to-action-state-v1"
    static let snapshotKey = "saved-to-action-widget-snapshot-v1"

    private static var defaults: UserDefaults {
        let suite = Bundle.main.object(forInfoDictionaryKey: "SavedToActionAppGroup") as? String
        return suite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func current() -> WidgetAction? {
        guard let snapshot = load() else { return nil }
        let open = snapshot.actions.filter {
            !snapshot.state.done.contains($0.id) && !snapshot.state.burned.contains($0.id)
        }
        return open.first(where: { $0.id == snapshot.state.currentAction }) ?? open.first
    }

    static func advance() {
        guard var snapshot = load() else { return }
        let open = snapshot.actions.filter {
            !snapshot.state.done.contains($0.id) && !snapshot.state.burned.contains($0.id)
        }
        guard !open.isEmpty else { return }
        let index = open.firstIndex(where: { $0.id == snapshot.state.currentAction }) ?? -1
        snapshot.state.currentAction = open[(index + 1) % open.count].id
        save(snapshot)
    }

    static func complete(_ id: String) {
        guard var snapshot = load() else { return }
        if !snapshot.state.done.contains(id) { snapshot.state.done.append(id) }
        snapshot.state.tracked.removeAll { $0 == id }
        snapshot.state.burned.removeAll { $0 == id }
        if snapshot.state.currentAction == id { snapshot.state.currentAction = nil }
        save(snapshot)
        advance()
    }

    private static func save(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        if let snapshotData = try? encoder.encode(snapshot) {
            defaults.set(snapshotData, forKey: snapshotKey)
        }
        if let stateData = try? encoder.encode(snapshot.state) {
            defaults.set(stateData, forKey: stateKey)
        }
    }
}
