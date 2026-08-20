import AppKit
import Foundation

@MainActor
enum SharedActionStore {
    static let stateKey = "saved-to-action-state-v1"

    private static var defaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["SAVED_TO_ACTION_DEFAULTS_SUITE"],
           let isolated = UserDefaults(suiteName: suite) {
            return isolated
        }
        return .standard
    }

    private static var appConfigURL: URL {
        if let override = ProcessInfo.processInfo.environment["SAVED_TO_ACTION_APP_CONFIG"] {
            return URL(fileURLWithPath: override)
        }
        let userConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SavedToAction/app.json")
        if FileManager.default.fileExists(atPath: userConfig.path) {
            return userConfig
        }
        return Bundle.main.url(forResource: "AppConfig", withExtension: "json") ?? userConfig
    }

    static func loadState() -> BoardState {
        guard
            let data = defaults.data(forKey: stateKey),
            let state = try? JSONDecoder().decode(BoardState.self, from: data)
        else { return BoardState() }
        return state
    }

    static func saveState(_ state: BoardState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    static func importState(from json: String) {
        guard
            let data = json.data(using: .utf8),
            let state = try? JSONDecoder().decode(BoardState.self, from: data)
        else { return }
        saveState(state)
    }

    static func loadActions() -> (configured: Bool, message: String, actions: [ActionItem], revisit: RevisitItem?) {
        guard let pointerData = try? Data(contentsOf: appConfigURL) else {
            return (false, "尚未配置工作目录。请先运行 saved-to-action configure-app。", [], nil)
        }
        guard
            let pointer = try? JSONDecoder().decode(AppPointer.self, from: pointerData),
            pointer.version == 1
        else { return (false, "App 配置损坏，请重新配置工作目录。", [], nil) }

        let workspaceURL = URL(fileURLWithPath: pointer.workspaceConfigPath).standardizedFileURL
        guard let workspaceData = try? Data(contentsOf: workspaceURL) else {
            return (false, "找不到工作目录配置，请确认目录仍然存在。", [], nil)
        }
        guard
            let config = try? JSONDecoder().decode(WorkspaceConfig.self, from: workspaceData),
            config.version == 1
        else { return (false, "工作目录配置无法解析。", [], nil) }

        let workspaceRoot = workspaceURL.deletingLastPathComponent().standardizedFileURL
        let dataURL = workspaceRoot.appendingPathComponent(config.dataPath).standardizedFileURL
        guard isInside(dataURL, root: workspaceRoot), let data = try? Data(contentsOf: dataURL) else {
            return (false, "行动数据不存在或超出工作目录。", [], nil)
        }
        guard
            let file = try? JSONDecoder().decode(ActionFile.self, from: data),
            file.version == 1
        else { return (false, "行动数据损坏；原文件没有被 App 修改。", [], nil) }

        var sourceRoots: [String: URL] = [:]
        var sourceNames: Set<String> = []
        for source in config.sources {
            guard sourceNames.insert(source.name).inserted else {
                return (false, "工作目录包含重复的来源名称。", [], nil)
            }
            if (source.kind ?? "markdown") == "markdown", let path = source.path {
                sourceRoots[source.name] = URL(fileURLWithPath: path)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
            }
        }
        var items = file.actions.map { action in
            ActionItem(stored: action, sourceURL: resolveSource(action, roots: sourceRoots))
        }
        let state = loadState()
        items.append(contentsOf: state.custom.map { action in
            let stored = StoredAction(
                id: action.id,
                sourceId: action.sourceId,
                sourceName: action.sourceName,
                relativePath: action.relativePath,
                collectionTitle: action.title,
                category: "待分类",
                intent: action.intent,
                task: action.task,
                detail: action.detail,
                savedAt: action.savedAt,
                sourceType: "旧收藏回看",
                sourceURL: action.sourceURL
            )
            return ActionItem(stored: stored, sourceURL: resolveSource(stored, roots: sourceRoots))
        })
        let revisit = file.dailyRevisit.map {
            RevisitItem(stored: $0, sourceURL: resolveSource($0, roots: sourceRoots))
        }
        let message = items.isEmpty ? "还没有行动卡。运行一次增量同步后，它们会出现在这里。" : ""
        return (true, message, items, revisit)
    }

    private static func resolveSource(_ action: StoredAction, roots: [String: URL]) -> URL? {
        if let remote = safeRemoteURL(action.sourceURL) { return remote }
        guard let root = roots[action.sourceName] else { return nil }
        let candidate = root.appendingPathComponent(action.relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard isInside(candidate, root: root), FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private static func resolveSource(_ revisit: StoredRevisit, roots: [String: URL]) -> URL? {
        if let remote = safeRemoteURL(revisit.sourceURL) { return remote }
        guard let root = roots[revisit.sourceName] else { return nil }
        let candidate = root.appendingPathComponent(revisit.relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard isInside(candidate, root: root), FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func safeRemoteURL(_ value: String?) -> URL? {
        guard
            let value,
            let url = URL(string: value),
            url.scheme?.lowercased() == "https",
            url.host != nil,
            url.user == nil,
            url.password == nil
        else { return nil }
        return url
    }

    static func allActions() -> [ActionItem] {
        loadActions().actions
    }

    static func openActions(state: BoardState? = nil) -> [ActionItem] {
        let state = state ?? loadState()
        return allActions().filter { !state.done.contains($0.id) && !state.burned.contains($0.id) }
    }

    static func currentAction() -> ActionItem? {
        var state = loadState()
        let open = openActions(state: state)
        guard !open.isEmpty else { return nil }
        if let id = state.currentAction, let current = open.first(where: { $0.id == id }) {
            return current
        }
        state.currentAction = open[0].id
        saveState(state)
        return open[0]
    }

    @discardableResult
    static func advanceAction() -> ActionItem? {
        var state = loadState()
        let open = openActions(state: state)
        guard !open.isEmpty else {
            state.currentAction = nil
            saveState(state)
            return nil
        }
        let index = open.firstIndex(where: { $0.id == state.currentAction }) ?? -1
        let next = open[(index + 1) % open.count]
        state.currentAction = next.id
        saveState(state)
        return next
    }

    static func complete(_ id: String) {
        var state = loadState()
        state.complete(id)
        saveState(state)
        _ = advanceAction()
    }

    static func burn(_ id: String) {
        var state = loadState()
        state.burn(id)
        saveState(state)
        _ = advanceAction()
    }

    static func toggleTracked(_ id: String) {
        var state = loadState()
        state.toggleTracked(id)
        saveState(state)
    }

    static func openSource(actionID: String) {
        guard let item = allActions().first(where: { $0.id == actionID }), let url = item.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    static func openRevisitSource() {
        guard let url = loadActions().revisit?.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    static func convertRevisit() -> String? {
        guard let revisit = loadActions().revisit else { return nil }
        let id = "revisit:\(String(revisit.stored.sourceId.suffix(24)))"
        var state = loadState()
        guard !state.custom.contains(where: { $0.id == id }) else { return id }
        state.custom.append(
            LocalAction(
                id: id,
                sourceId: revisit.stored.sourceId,
                sourceName: revisit.stored.sourceName,
                relativePath: revisit.stored.relativePath,
                title: revisit.stored.title,
                task: revisit.stored.task,
                intent: revisit.stored.summary,
                detail: revisit.stored.detail,
                savedAt: revisit.stored.savedAt,
                sourceURL: revisit.stored.sourceURL
            )
        )
        state.currentAction = id
        saveState(state)
        return id
    }

    static func boardPayload() -> BoardPayload {
        let loaded = loadActions()
        let state = loadState()
        let revisitID = loaded.revisit.map { "revisit:\(String($0.stored.sourceId.suffix(24)))" }
        return BoardPayload(
            configured: loaded.configured,
            message: loaded.message,
            state: state,
            actions: loaded.actions.map {
                BoardAction(
                    id: $0.id,
                    title: $0.title,
                    category: $0.category,
                    intent: $0.intent,
                    task: $0.task,
                    detail: $0.detail,
                    savedDays: $0.savedDays,
                    sourceName: $0.sourceName,
                    sourceType: $0.sourceType,
                    hasSource: $0.sourceURL != nil
                )
            },
            dailyRevisit: loaded.revisit.map {
                BoardRevisit(
                    sourceId: $0.stored.sourceId,
                    title: $0.stored.title,
                    summary: $0.stored.summary,
                    usage: $0.stored.usage,
                    task: $0.stored.task,
                    detail: $0.stored.detail,
                    savedDays: $0.savedDays,
                    selectedAt: $0.stored.selectedAt,
                    hasSource: $0.sourceURL != nil,
                    converted: revisitID.map { id in state.custom.contains(where: { $0.id == id }) } ?? false
                )
            }
        )
    }

    static func boardPayloadBase64() -> String {
        guard let data = try? JSONEncoder().encode(boardPayload()) else { return "" }
        return data.base64EncodedString()
    }

}
