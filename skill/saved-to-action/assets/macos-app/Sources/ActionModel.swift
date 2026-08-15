import Foundation

@MainActor
final class ActionModel: ObservableObject {
    @Published private(set) var action: ActionItem?
    @Published private(set) var statusMessage = ""
    @Published private(set) var completedCount = 0
    @Published private(set) var isTracked = false

    init() { reload() }

    func reload() {
        let loaded = SharedActionStore.loadActions()
        statusMessage = loaded.message
        action = SharedActionStore.currentAction()
        let state = SharedActionStore.loadState()
        completedCount = state.done.count
        isTracked = action.map { state.tracked.contains($0.id) } ?? false
    }

    func next() {
        action = SharedActionStore.advanceAction()
        reload()
    }

    func completeCurrent() {
        guard let action else { return }
        SharedActionStore.complete(action.id)
        reload()
    }

    func burnCurrent() {
        guard let action else { return }
        SharedActionStore.burn(action.id)
        reload()
    }

    func toggleTracked() {
        guard let action else { return }
        SharedActionStore.toggleTracked(action.id)
        reload()
    }

    func openCurrentSource() {
        guard let action else { return }
        SharedActionStore.openSource(actionID: action.id)
    }
}
