import SwiftUI

/// 贪吃蛇游戏界面：棋盘 + 分数 + 方向键，支持滑动与点按操作
@MainActor
struct SnakeGameView: View {

    @StateObject private var game = SnakeGame()
    @Environment(\.scenePhase) private var scenePhase

    private let boardCornerRadius: CGFloat = 24
    private let padButtonSize: CGFloat = 64

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.13, blue: 0.16),
                    Color(red: 0.03, green: 0.05, blue: 0.07),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                boardSection
                directionPad
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 560)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                game.pauseIfRunning()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: game.eatCount)
        .sensoryFeedback(.error, trigger: game.crashCount)
    }

    // MARK: - 顶部信息

    private var header: some View {
        HStack(spacing: 10) {
            scoreCard(title: "得分", value: "\(game.score)")
            scoreCard(title: "最高", value: "\(game.bestScore)")

            Spacer(minLength: 0)

            Button {
                game.togglePause()
            } label: {
                Image(systemName: game.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(game.state == .gameOver)
            .opacity(game.state == .gameOver ? 0.35 : 1)
            .accessibilityLabel(Text(game.state == .running ? "暂停" : "开始或继续"))
        }
    }

    private func scoreCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - 棋盘

    private var boardSection: some View {
        Canvas { context, size in
            drawBoard(in: &context, size: size)
        }
        .aspectRatio(CGFloat(game.columns) / CGFloat(game.rows), contentMode: .fit)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay { statusOverlay }
        .clipShape(RoundedRectangle(cornerRadius: boardCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        .animation(.easeInOut(duration: 0.18), value: game.state)
    }

    private func drawBoard(in context: inout GraphicsContext, size: CGSize) {
        let cellSize = min(
            size.width / CGFloat(game.columns),
            size.height / CGFloat(game.rows)
        )
        let boardWidth = cellSize * CGFloat(game.columns)
        let boardHeight = cellSize * CGFloat(game.rows)
        let originX = (size.width - boardWidth) / 2
        let originY = (size.height - boardHeight) / 2

        // 网格线
        var gridPath = Path()
        for column in 1..<game.columns {
            let x = originX + CGFloat(column) * cellSize
            gridPath.move(to: CGPoint(x: x, y: originY))
            gridPath.addLine(to: CGPoint(x: x, y: originY + boardHeight))
        }
        for row in 1..<game.rows {
            let y = originY + CGFloat(row) * cellSize
            gridPath.move(to: CGPoint(x: originX, y: y))
            gridPath.addLine(to: CGPoint(x: originX + boardWidth, y: y))
        }
        context.stroke(gridPath, with: .color(Color.white.opacity(0.04)), lineWidth: 0.6)

        // 蛇身
        let inset = cellSize * 0.06
        for (index, point) in game.snake.enumerated() {
            let rect = CGRect(
                x: originX + CGFloat(point.x) * cellSize + inset,
                y: originY + CGFloat(point.y) * cellSize + inset,
                width: cellSize - inset * 2,
                height: cellSize - inset * 2
            )
            let path = Path(roundedRect: rect, cornerRadius: cellSize * 0.3)
            let color = index == 0
                ? Color(red: 0.58, green: 0.95, blue: 0.62)
                : bodyColor(for: index)
            context.fill(path, with: .color(color))
        }

        // 蛇头的眼睛，指示前进方向
        if let head = game.snake.first {
            let center = CGPoint(
                x: originX + (CGFloat(head.x) + 0.5) * cellSize,
                y: originY + (CGFloat(head.y) + 0.5) * cellSize
            )
            let forward = game.heading.vector
            let forwardX = CGFloat(forward.x)
            let forwardY = CGFloat(forward.y)
            let sideX = -forwardY
            let sideY = forwardX
            let eyeRadius = cellSize * 0.085

            for sign in [CGFloat(-1), CGFloat(1)] {
                let eyeCenter = CGPoint(
                    x: center.x + forwardX * cellSize * 0.16 + sideX * cellSize * 0.17 * sign,
                    y: center.y + forwardY * cellSize * 0.16 + sideY * cellSize * 0.17 * sign
                )
                let rect = CGRect(
                    x: eyeCenter.x - eyeRadius,
                    y: eyeCenter.y - eyeRadius,
                    width: eyeRadius * 2,
                    height: eyeRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.05, green: 0.14, blue: 0.09)))
            }
        }

        // 食物（带一点光晕）
        let foodCenter = CGPoint(
            x: originX + (CGFloat(game.food.x) + 0.5) * cellSize,
            y: originY + (CGFloat(game.food.y) + 0.5) * cellSize
        )
        let foodRadius = cellSize * 0.3
        let foodRect = CGRect(
            x: foodCenter.x - foodRadius,
            y: foodCenter.y - foodRadius,
            width: foodRadius * 2,
            height: foodRadius * 2
        )
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.orange.opacity(0.65), radius: cellSize * 0.4))
            layer.fill(
                Path(ellipseIn: foodRect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(red: 1.0, green: 0.88, blue: 0.5),
                        Color(red: 0.98, green: 0.45, blue: 0.24),
                    ]),
                    center: foodCenter,
                    startRadius: 0,
                    endRadius: foodRadius
                )
            )
        }
    }

    private func bodyColor(for index: Int) -> Color {
        let lastIndex = max(game.snake.count - 1, 1)
        let progress = min(Double(index) / Double(lastIndex), 1)
        return Color(
            hue: 0.37 - progress * 0.07,
            saturation: 0.55 + progress * 0.18,
            brightness: 0.86 - progress * 0.32
        )
    }

    // MARK: - 状态遮罩

    @ViewBuilder
    private var statusOverlay: some View {
        switch game.state {
        case .running:
            EmptyView()
        case .ready:
            overlayPanel {
                Text("贪吃蛇")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("滑动棋盘或点按方向键控制小蛇\n吃到食物得分，撞墙或撞到自己就结束")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Button("开始游戏") { game.start() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        case .paused:
            overlayPanel {
                Text("已暂停")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Button("继续") { game.togglePause() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        case .gameOver:
            overlayPanel {
                Text(game.didWin ? "太厉害了，全部吃光！" : "撞到啦")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("本局得分 \(game.score)　最高 \(game.bestScore)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Button("再来一局") { game.start() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func overlayPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.66)

            VStack(spacing: 14) {
                content()
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(20)
        }
    }

    // MARK: - 操作

    private var directionPad: some View {
        VStack(spacing: 8) {
            padButton(.up, systemName: "chevron.up", label: "向上")
            HStack(spacing: 8) {
                padButton(.left, systemName: "chevron.left", label: "向左")
                Color.clear.frame(width: padButtonSize, height: padButtonSize)
                padButton(.right, systemName: "chevron.right", label: "向右")
            }
            padButton(.down, systemName: "chevron.down", label: "向下")
        }
        .padding(.top, 4)
    }

    private func padButton(_ direction: Direction, systemName: String, label: String) -> some View {
        Button {
            game.handleInput(direction)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: padButtonSize, height: padButtonSize)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard max(abs(dx), abs(dy)) > 12 else { return }

                if abs(dx) > abs(dy) {
                    game.handleInput(dx > 0 ? .right : .left)
                } else {
                    game.handleInput(dy > 0 ? .down : .up)
                }
            }
    }
}

/// 遮罩里的主操作按钮样式
private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Color.green.opacity(configuration.isPressed ? 0.6 : 0.9))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

#Preview {
    SnakeGameView()
}
