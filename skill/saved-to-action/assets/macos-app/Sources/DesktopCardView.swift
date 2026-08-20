import SwiftUI

struct DesktopCardView: View {
    @ObservedObject var model: ActionModel
    let openBoard: () -> Void
    @State private var showingBurnConfirmation = false
    @State private var burnProgress: CGFloat = 0

    private let ink = Color(red: 0.18, green: 0.15, blue: 0.12)
    private let wine = Color(red: 0.58, green: 0.28, blue: 0.18)
    private let muted = Color(red: 0.38, green: 0.31, blue: 0.25)
    private let line = Color(red: 0.63, green: 0.51, blue: 0.37)
    private let paper = Color(red: 0.95, green: 0.91, blue: 0.82)

    var body: some View {
        Group {
            if let action = model.action {
                actionCard(action)
            } else {
                emptyCard
            }
        }
        .frame(width: 410, height: 470)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(paper.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(line.opacity(0.48), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 12)
        )
        .mask {
            ParticleDissolveMask(progress: burnProgress)
        }
        .overlay {
            ParticleDissolveOverlay(progress: burnProgress, wine: wine, ink: ink)
                .allowsHitTesting(false)
        }
        .saturation(1 - Double(burnProgress) * 0.45)
        .allowsHitTesting(burnProgress == 0)
        .padding(22)
    }

    private func actionCard(_ action: ActionItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(wine)
                    Text("今日行动")
                        .font(.system(size: 27, weight: .bold, design: .serif))
                        .foregroundStyle(ink)
                    Text("把曾经留下的，慢慢变成正在发生的。")
                        .font(.system(size: 9, weight: .semibold, design: .serif))
                        .foregroundStyle(muted.opacity(0.9))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("已收藏 \(action.savedDays) 天")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(line, lineWidth: 1))
            }

            HStack(spacing: 9) {
                Rectangle().fill(line).frame(height: 1)
                Text("01")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(wine)
            }
            .padding(.vertical, 14)

            Text("来自「\(action.title)」")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(muted)
                .lineLimit(1)

            Text(action.intent)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(muted)
                .lineSpacing(4)
                .lineLimit(3)
                .padding(.top, 10)

            Text(action.task)
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .lineSpacing(4)
                .lineLimit(4)
                .padding(.top, 14)

            if let detail = action.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(muted.opacity(0.9))
                    .lineSpacing(3)
                    .lineLimit(2)
                    .padding(.top, 8)
            }

            Spacer(minLength: 14)

            HStack(spacing: 8) {
                Button(action: model.next) {
                    Label("换一张", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DesktopOutlineButtonStyle(color: muted, line: line))

                if action.sourceURL != nil {
                    Button(action: model.openCurrentSource) {
                        Text("查看原文")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DesktopOutlineButtonStyle(color: muted, line: line))
                }

                Button(action: model.completeCurrent) {
                    Text("完成")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DesktopFilledButtonStyle(color: muted))
            }

            HStack {
                Button {
                    showingBurnConfirmation = true
                } label: {
                    Text("阅后即焚")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(wine)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: openBoard) {
                    HStack(spacing: 5) {
                        Text("打开完整看板")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(26)
        .alert("阅后即焚", isPresented: $showingBurnConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认焚烧", role: .destructive) {
                beginBurn()
            }
        } message: {
            Text("这张行动卡将被永久关闭，不再出现在提醒中。收藏原文仍保留在知识库里。")
        }
    }

    private func beginBurn() {
        guard burnProgress == 0 else { return }
        withAnimation(.linear(duration: 1.4)) {
            burnProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.44) {
            model.burnCurrent()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                burnProgress = 0
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 10, weight: .bold, design: .serif))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(wine)
            Text("今日行动")
                .font(.system(size: 27, weight: .bold, design: .serif))
                .foregroundStyle(ink)
            Text("把曾经留下的，慢慢变成正在发生的。")
                .font(.system(size: 10, weight: .semibold, design: .serif))
                .foregroundStyle(muted.opacity(0.9))
            Rectangle()
                .fill(line)
                .frame(height: 1)
                .padding(.vertical, 8)
            Text(model.statusMessage.isEmpty ? "目前没有仍开放的行动卡。" : model.statusMessage)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(muted)
                .lineSpacing(4)
            Button("打开完整看板", action: openBoard)
                .buttonStyle(DesktopFilledButtonStyle(color: muted))
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(26)
    }
}

private struct ParticleDissolveMask: View, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            if progress <= 0.001 {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                return
            }
            guard progress < 0.999 else { return }

            let frontier = size.width * progress
            let featherWidth = min(CGFloat(34), size.width)
            let featherStart = max(CGFloat(0), frontier - featherWidth * 0.45)
            let stripWidth = featherWidth / 10

            for step in 0..<10 {
                let opacity = Double(step + 1) / 10
                let x = featherStart + CGFloat(step) * stripWidth
                context.opacity = opacity
                context.fill(
                    Path(CGRect(x: x, y: 0, width: stripWidth + 0.5, height: size.height)),
                    with: .color(.white)
                )
            }

            let solidStart = min(size.width, featherStart + featherWidth)
            context.opacity = 1
            context.fill(
                Path(CGRect(x: solidStart, y: 0, width: size.width - solidStart, height: size.height)),
                with: .color(.white)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct ParticleDissolveOverlay: View, Animatable {
    var progress: CGFloat
    let wine: Color
    let ink: Color

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let current = Double(progress)
            guard current > 0 else { return }

            for index in 0..<320 {
                let birth = random(index, salt: 17)
                let age = current - birth
                let lifetime = 0.28 + random(index, salt: 43) * 0.12
                guard age >= 0, age <= lifetime else { continue }

                let phase = age / lifetime
                let originX = size.width * CGFloat(birth)
                let originY = size.height * CGFloat(random(index, salt: 71))
                let drift = CGFloat(phase) * (32 + CGFloat(random(index, salt: 89)) * 72)
                let lift = CGFloat(phase) * (12 + CGFloat(random(index, salt: 101)) * 58)
                let wobble = sin(CGFloat(phase) * .pi * 2 + CGFloat(index)) * 8
                let x = originX - drift
                let y = originY - lift + wobble
                let particleSize = 2.2 + CGFloat(random(index, salt: 127)) * 4.8
                let opacity = max(0, 1 - phase)

                var triangle = Path()
                triangle.move(to: CGPoint(x: x, y: y - particleSize))
                triangle.addLine(to: CGPoint(x: x + particleSize, y: y + particleSize * 0.72))
                triangle.addLine(to: CGPoint(x: x - particleSize * 0.78, y: y + particleSize * 0.45))
                triangle.closeSubpath()

                context.opacity = opacity * 0.92
                context.fill(triangle, with: .color(particleColor(index)))
            }
        }
        .allowsHitTesting(false)
    }

    private func particleColor(_ index: Int) -> Color {
        switch index % 5 {
        case 0:
            return Color(red: 0.78, green: 0.66, blue: 0.48)
        case 1, 2:
            return wine.opacity(0.92)
        default:
            return ink.opacity(0.94)
        }
    }

    private func random(_ index: Int, salt: Int) -> Double {
        var value = UInt64(index &* 1_103_515_245 &+ salt &* 12_345)
        value ^= value >> 16
        value &*= 0x7feb_352d
        value ^= value >> 15
        return Double(value % 10_000) / 10_000
    }
}

private struct DesktopOutlineButtonStyle: ButtonStyle {
    let color: Color
    let line: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Color.white.opacity(0.4) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(line, lineWidth: 1))
    }
}

private struct DesktopFilledButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.89))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? color.opacity(0.8) : color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
