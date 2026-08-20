import Foundation

struct AppPointer: Decodable {
    let version: Int
    let workspaceConfigPath: String
}

struct WorkspaceConfig: Decodable {
    let version: Int
    let sources: [SourceConfig]
    let dataPath: String
}

struct SourceConfig: Decodable {
    let name: String
    let path: String
}

struct ActionFile: Decodable {
    let version: Int
    let updatedAt: String?
    let actions: [StoredAction]
    let dailyRevisit: StoredRevisit?
}

struct StoredAction: Decodable, Identifiable, Hashable {
    let id: String
    let sourceId: String
    let sourceName: String
    let relativePath: String
    let collectionTitle: String
    let category: String
    let intent: String
    let task: String
    let detail: String?
    let savedAt: String
    let sourceType: String
}

struct StoredRevisit: Decodable, Hashable {
    let sourceId: String
    let sourceName: String
    let relativePath: String
    let title: String
    let summary: String
    let usage: String
    let task: String
    let detail: String?
    let savedAt: String
    let selectedAt: String
}

struct LocalAction: Codable, Equatable, Identifiable {
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

struct BoardState: Codable, Equatable {
    var done: [String] = []
    var tracked: [String] = []
    var burned: [String] = []
    var currentAction: String?
    var custom: [LocalAction] = []

    enum CodingKeys: String, CodingKey { case done, tracked, burned, currentAction, custom }

    init(
        done: [String] = [],
        tracked: [String] = [],
        burned: [String] = [],
        currentAction: String? = nil,
        custom: [LocalAction] = []
    ) {
        self.done = done
        self.tracked = tracked
        self.burned = burned
        self.currentAction = currentAction
        self.custom = custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = try container.decodeIfPresent([String].self, forKey: .done) ?? []
        tracked = try container.decodeIfPresent([String].self, forKey: .tracked) ?? []
        burned = try container.decodeIfPresent([String].self, forKey: .burned) ?? []
        currentAction = try container.decodeIfPresent(String.self, forKey: .currentAction)
        custom = try container.decodeIfPresent([LocalAction].self, forKey: .custom) ?? []
    }

    mutating func complete(_ id: String) {
        if !done.contains(id) { done.append(id) }
        tracked.removeAll { $0 == id }
        burned.removeAll { $0 == id }
        if currentAction == id { currentAction = nil }
    }

    mutating func burn(_ id: String) {
        if !burned.contains(id) { burned.append(id) }
        done.removeAll { $0 == id }
        tracked.removeAll { $0 == id }
        if currentAction == id { currentAction = nil }
    }

    mutating func toggleTracked(_ id: String) {
        if tracked.contains(id) {
            tracked.removeAll { $0 == id }
        } else {
            tracked.append(id)
        }
    }
}

struct ActionItem: Identifiable, Hashable {
    let stored: StoredAction
    let sourceURL: URL?

    var id: String { stored.id }
    var title: String { stored.collectionTitle }
    var category: String { stored.category }
    var intent: String { stored.intent }
    var task: String { stored.task }
    var detail: String? { stored.detail }
    var sourceName: String { stored.sourceName }
    var sourceType: String { stored.sourceType }

    var savedDays: Int {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let savedDate = formatter.date(from: stored.savedAt) else { return 0 }
        return max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: savedDate, to: Date()).day ?? 0)
    }
}

struct BoardAction: Codable {
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

struct RevisitItem: Hashable {
    let stored: StoredRevisit
    let sourceURL: URL?

    var savedDays: Int { daysSince(stored.savedAt) }
}

struct BoardRevisit: Encodable {
    let sourceId: String
    let title: String
    let summary: String
    let usage: String
    let task: String
    let detail: String?
    let savedDays: Int
    let selectedAt: String
    let hasSource: Bool
    let converted: Bool
}

struct BoardPayload: Encodable {
    let configured: Bool
    let message: String
    let state: BoardState
    let actions: [BoardAction]
    let dailyRevisit: BoardRevisit?
}

func daysSince(_ dateString: String) -> Int {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let savedDate = formatter.date(from: dateString) else { return 0 }
    return max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: savedDate, to: Date()).day ?? 0)
}
