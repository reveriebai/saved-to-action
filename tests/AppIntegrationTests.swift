import AppKit
import Darwin
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private func writeJSON(_ value: Any, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

@main
@MainActor
struct AppIntegrationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("saved-to-action-app-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let pointerURL = root.appendingPathComponent("AppConfig.json")
        let suite = "io.github.saved-to-action.tests.\(UUID().uuidString)"
        setenv("SAVED_TO_ACTION_APP_CONFIG", pointerURL.path, 1)
        setenv("SAVED_TO_ACTION_DEFAULTS_SUITE", suite, 1)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var loaded = SharedActionStore.loadActions()
        require(!loaded.configured && loaded.actions.isEmpty, "missing config should show a safe empty state")

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: pointerURL)
        loaded = SharedActionStore.loadActions()
        require(!loaded.configured && loaded.message.contains("损坏"), "damaged app config should degrade")

        let source = root.appendingPathComponent("notes")
        let workspace = root.appendingPathComponent("workspace")
        let configURL = workspace.appendingPathComponent("saved-to-action.json")
        let dataURL = workspace.appendingPathComponent("Data/actions.json")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("# 示例\n".utf8).write(to: source.appendingPathComponent("example.md"))
        try writeJSON(["version": 1, "workspaceConfigPath": configURL.path], to: pointerURL)
        try writeJSON([
            "version": 1,
            "sources": [
                ["name": "示例", "kind": "markdown", "path": source.path],
                ["name": "远程", "kind": "getnote"],
            ],
            "dataPath": "Data/actions.json",
        ], to: configURL)
        try writeJSON(["version": 1, "updatedAt": "2026-01-01", "actions": []], to: dataURL)
        loaded = SharedActionStore.loadActions()
        require(loaded.configured && loaded.actions.isEmpty && loaded.message.contains("还没有行动卡"), "valid empty workspace should render empty state")

        try Data("not-json".utf8).write(to: dataURL, options: .atomic)
        loaded = SharedActionStore.loadActions()
        require(!loaded.configured && loaded.message.contains("损坏"), "damaged action JSON should degrade")

        func action(_ id: String, _ path: String) -> [String: Any] {
            [
                "id": id, "sourceId": "note:1", "sourceName": "示例", "relativePath": path,
                "collectionTitle": "示例", "category": "待分类", "intent": "想验证方法。",
                "task": "打开示例，写下一句话。", "detail": NSNull(), "savedAt": "2026-01-01",
                "sourceType": "Markdown 笔记",
            ]
        }

        func remoteAction(_ id: String, _ sourceURL: String) -> [String: Any] {
            [
                "id": id, "sourceId": "note:remote", "sourceName": "远程", "relativePath": "notes/demo",
                "collectionTitle": "远程示例", "category": "待分类", "intent": "想验证远程来源。",
                "task": "打开原文，写下一句话。", "detail": NSNull(), "savedAt": "2026-01-01",
                "sourceType": "Get笔记网页收藏", "sourceURL": sourceURL,
            ]
        }

        try writeJSON(["version": 1, "updatedAt": "2026-01-01", "actions": [action("a1", "../outside.md")]], to: dataURL)
        loaded = SharedActionStore.loadActions()
        require(loaded.configured && loaded.actions.count == 1 && loaded.actions[0].sourceURL == nil, "source traversal must disable open-original")

        try writeJSON(["version": 1, "updatedAt": "2026-01-01", "actions": [action("a1", "example.md"), action("a2", "example.md")]], to: dataURL)
        loaded = SharedActionStore.loadActions()
        require(loaded.actions.count == 2 && loaded.actions.allSatisfy { $0.sourceURL != nil }, "incremental refresh should load new actions")

        try writeJSON([
            "version": 1,
            "updatedAt": "2026-01-01",
            "actions": [remoteAction("remote-ok", "https://www.apple.com/notes"), remoteAction("remote-bad", "file:///outside")],
        ], to: dataURL)
        loaded = SharedActionStore.loadActions()
        require(loaded.actions[0].sourceURL?.scheme == "https", "verified HTTPS source should remain openable")
        require(loaded.actions[1].sourceURL == nil, "non-HTTPS remote source must not be openable")

        let revisit: [String: Any] = [
            "sourceId": "note:history", "sourceName": "示例", "relativePath": "example.md",
            "title": "旧笔记", "summary": "它记录了一个值得重看的方法。",
            "usage": "需要重新判断下一步时。", "task": "打开旧笔记，写下一条验证问题。",
            "detail": NSNull(), "savedAt": "2026-01-01", "selectedAt": "2026-08-20",
        ]
        try writeJSON([
            "version": 1,
            "updatedAt": "2026-01-01",
            "actions": [action("a1", "example.md"), action("a2", "example.md")],
            "dailyRevisit": revisit,
        ], to: dataURL)
        loaded = SharedActionStore.loadActions()
        require(loaded.revisit?.sourceURL != nil, "daily revisit should resolve its original Markdown safely")
        require(SharedActionStore.convertRevisit() != nil, "daily revisit should convert to a local action")
        require(SharedActionStore.loadState().custom.count == 1, "converted revisit should stay in local state")
        require(SharedActionStore.loadActions().actions.count == 3, "converted revisit should appear with regular actions")

        var state = BoardState(currentAction: "a1")
        state.toggleTracked("a1")
        require(state.tracked == ["a1"], "tracking should toggle on")
        state.complete("a1")
        require(state.done == ["a1"] && state.tracked.isEmpty && state.burned.isEmpty, "complete must not leak into other states")
        state.burn("a1")
        require(state.burned == ["a1"] && state.done.isEmpty && state.tracked.isEmpty, "burn must be mutually exclusive")

        SharedActionStore.saveState(state)
        require(SharedActionStore.loadState() == state, "state should survive a UserDefaults round trip")
        let legacy = try JSONDecoder().decode(BoardState.self, from: Data("{\"done\":[\"old\"],\"tracked\":[],\"burned\":[],\"currentAction\":null}".utf8))
        require(legacy.custom.isEmpty && legacy.done == ["old"], "state migration should accept pre-revisit data")
        print("App integration tests passed")
    }
}
