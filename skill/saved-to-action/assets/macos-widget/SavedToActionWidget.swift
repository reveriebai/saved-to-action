import SwiftUI
import WidgetKit

struct SavedActionEntry: TimelineEntry {
    let date: Date
    let action: WidgetAction?
}

struct SavedActionProvider: TimelineProvider {
    func placeholder(in context: Context) -> SavedActionEntry { SavedActionEntry(date: Date(), action: nil) }
    func getSnapshot(in context: Context, completion: @escaping (SavedActionEntry) -> Void) {
        completion(SavedActionEntry(date: Date(), action: SavedToActionWidgetStore.current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SavedActionEntry>) -> Void) {
        completion(Timeline(entries: [SavedActionEntry(date: Date(), action: SavedToActionWidgetStore.current())], policy: .never))
    }
}

struct SavedActionWidgetView: View {
    let entry: SavedActionEntry
    private let ink = Color(red: 0.18, green: 0.14, blue: 0.12)
    private let wine = Color(red: 0.59, green: 0.25, blue: 0.18)
    private let paper = Color(red: 0.95, green: 0.89, blue: 0.80)

    var body: some View {
        Group {
            if let action = entry.action {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("SAVED TO ACTION").font(.caption.bold()).tracking(1.5).foregroundStyle(wine); Spacer(); Text("\(action.savedDays) 天").font(.caption) }
                    Divider().overlay(ink)
                    Text(action.category).font(.caption.bold()).foregroundStyle(wine)
                    Text(action.task).font(.system(size: 22, weight: .bold, design: .serif)).lineLimit(4)
                    Text(action.intent).font(.system(size: 12, design: .serif)).foregroundStyle(ink.opacity(0.72)).lineLimit(3)
                    Spacer()
                    HStack {
                        Button(intent: NextSavedActionIntent()) { Label("换一张", systemImage: "arrow.clockwise") }
                        Button(intent: CompleteSavedActionIntent(actionID: action.id)) { Text("完成") }
                    }.buttonStyle(.bordered)
                    Link("打开完整看板 ↗", destination: URL(string: "savedtoaction://board")!).font(.caption.bold())
                }.padding(20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("收藏行动").font(.system(size: 25, weight: .bold, design: .serif))
                    Text("请先启动 Saved to Action App，让组件读取本机行动。")
                    Link("打开 App", destination: URL(string: "savedtoaction://board")!)
                }.padding(20)
            }
        }
        .foregroundStyle(ink)
        .containerBackground(for: .widget) { paper }
    }
}

struct SavedToActionWidget: Widget {
    let kind = "SavedToActionWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SavedActionProvider()) { SavedActionWidgetView(entry: $0) }
            .configurationDisplayName("收藏行动")
            .description("从本机收藏中挑出一件可以开始的小事。")
            .supportedFamilies([.systemLarge])
    }
}

@main
struct SavedToActionWidgetBundle: WidgetBundle {
    var body: some Widget { SavedToActionWidget() }
}
