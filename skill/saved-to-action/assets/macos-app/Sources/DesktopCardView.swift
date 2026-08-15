import SwiftUI

struct DesktopCardView: View {
    @ObservedObject var model: ActionModel
    let openBoard: () -> Void

    private let paper = Color(red: 0.95, green: 0.89, blue: 0.80)
    private let ink = Color(red: 0.18, green: 0.14, blue: 0.12)
    private let wine = Color(red: 0.58, green: 0.22, blue: 0.15)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(paper)
            RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.75), lineWidth: 1)
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider().overlay(ink)
                if let action = model.action { actionContent(action) } else { emptyContent }
                Spacer(minLength: 0)
                footer
            }
            .padding(24)
        }
        .padding(7)
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("PERSONAL ARCHIVE / TODAY")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(wine)
                Text("收藏行动")
                    .font(.system(size: 33, weight: .black, design: .serif))
                    .foregroundStyle(ink)
            }
            Spacer()
            Text("\(model.completedCount) 件落地")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(wine)
        }
    }

    private func actionContent(_ action: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(action.category.uppercased())
                Spacer()
                Text("已保存 \(action.savedDays) 天")
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(wine)
            Text(action.task)
                .font(.system(size: 25, weight: .bold, design: .serif))
                .lineSpacing(3)
                .foregroundStyle(ink)
            Text(action.intent)
                .font(.system(size: 13, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(ink.opacity(0.78))
            if let detail = action.detail, !detail.isEmpty {
                Text("怎么做  ·  \(detail)")
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(ink.opacity(0.65))
            }
            HStack(spacing: 8) {
                actionButton("完成", filled: true, action: model.completeCurrent)
                actionButton(model.isTracked ? "取消追踪" : "保留追踪", action: model.toggleTracked)
                actionButton("换一张", action: model.next)
            }
            HStack(spacing: 8) {
                if action.sourceURL != nil { actionButton("打开原文", action: model.openCurrentSource) }
                actionButton("阅后即焚", action: model.burnCurrent)
            }
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("等待下一张行动卡")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(ink)
            Text(model.statusMessage)
                .font(.system(size: 13, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(ink.opacity(0.7))
            actionButton("打开完整看板", filled: true, action: openBoard)
        }
    }

    private var footer: some View {
        Button(action: openBoard) {
            HStack {
                Text("把曾经留下的，慢慢变成正在发生的。")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(wine)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? paper : wine)
            .background(filled ? wine : Color.clear)
            .overlay(Rectangle().stroke(wine.opacity(0.8), lineWidth: 1))
    }
}
