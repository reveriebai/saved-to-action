import AppIntents
import WidgetKit

struct NextSavedActionIntent: AppIntent {
    static var title: LocalizedStringResource = "换一张行动"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        SavedToActionWidgetStore.advance()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompleteSavedActionIntent: AppIntent {
    static var title: LocalizedStringResource = "完成行动"
    static var openAppWhenRun = false

    @Parameter(title: "行动 ID") var actionID: String

    init() { actionID = "" }
    init(actionID: String) { self.actionID = actionID }

    func perform() async throws -> some IntentResult {
        if !actionID.isEmpty { SavedToActionWidgetStore.complete(actionID) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
