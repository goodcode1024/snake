import Combine
import Foundation

// MARK: - 基础类型

/// 棋盘坐标，左上角为原点 (0, 0)
struct GridPoint: Hashable {
    var x: Int
    var y: Int

    /// 沿某个方向移动一格后的坐标
    func moved(_ direction: Direction) -> GridPoint {
        GridPoint(x: x + direction.vector.x, y: y + direction.vector.y)
    }
}

/// 移动方向
enum Direction: CaseIterable {
    case up
    case down
    case left
    case right

    var vector: (x: Int, y: Int) {
        switch self {
        case .up: return (0, -1)
        case .down: return (0, 1)
        case .left: return (-1, 0)
        case .right: return (1, 0)
        }
    }

    /// 是否为相反方向（蛇不能直接掉头）
    func isOpposite(of other: Direction) -> Bool {
        vector.x == -other.vector.x && vector.y == -other.vector.y
    }
}

/// 游戏状态
enum SnakeGameState: Equatable {
    case ready
    case running
    case paused
    case gameOver
}

// MARK: - 游戏模型

/// 贪吃蛇的游戏规则，全部在这个模型里，界面只负责展示与输入
@MainActor
final class SnakeGame: ObservableObject {

    static let columns = 20
    static let rows = 20
    static let pointsPerFood = 10

    private static let bestScoreKey = "snake.bestScore"
    private static let initialLength = 3

    /// 蛇身，第 0 个元素是蛇头
    @Published private(set) var snake: [GridPoint]
    /// 当前食物的位置
    @Published private(set) var food: GridPoint
    /// 当前实际前进方向
    @Published private(set) var heading: Direction = .right
    @Published private(set) var score = 0
    @Published private(set) var bestScore = 0
    @Published private(set) var state: SnakeGameState = .ready
    /// 是否因为吃满整个棋盘而获胜
    @Published private(set) var didWin = false
    /// 吃到食物次数，供界面触发触感反馈
    @Published private(set) var eatCount = 0
    /// 游戏结束次数，供界面触发触感反馈
    @Published private(set) var crashCount = 0

    private var queuedDirection: Direction?
    private var loopTask: Task<Void, Never>?

    var columns: Int { Self.columns }
    var rows: Int { Self.rows }

    /// 每次移动的间隔（秒），吃得越多跑得越快
    var tickInterval: TimeInterval {
        let eaten = Double(score) / Double(Self.pointsPerFood)
        return max(0.07, 0.17 - eaten * 0.005)
    }

    init() {
        let centerY = Self.rows / 2
        let headX = Self.columns / 2 + 1
        snake = (0..<Self.initialLength).map { offset in
            GridPoint(x: headX - offset, y: centerY)
        }
        food = GridPoint(x: headX + 4, y: centerY)
        bestScore = UserDefaults.standard.integer(forKey: Self.bestScoreKey)
        placeFood()
    }

    // MARK: - 对外操作

    /// 统一的输入入口：分为「开始并转向」与「仅转向」两种情况
    func handleInput(_ newDirection: Direction) {
        switch state {
        case .ready:
            start()
            // 开局时允许选择方向，但不能与初始朝向右相反
            if !newDirection.isOpposite(of: heading) {
                heading = newDirection
            }
        case .running:
            queue(newDirection)
        case .paused, .gameOver:
            break
        }
    }

    /// 开始（或重新开始）一局
    func start() {
        resetBoard()
        state = .running
        startLoop()
    }

    /// 暂停 / 继续；在准备阶段调用即开始游戏
    func togglePause() {
        switch state {
        case .running:
            state = .paused
            stopLoop()
        case .paused:
            state = .running
            startLoop()
        case .ready, .gameOver:
            start()
        }
    }

    /// 进入后台时自动暂停
    func pauseIfRunning() {
        guard state == .running else { return }
        state = .paused
        stopLoop()
    }

    // MARK: - 规则

    private func resetBoard() {
        let centerY = Self.rows / 2
        let headX = Self.columns / 2 + 1
        snake = (0..<Self.initialLength).map { offset in
            GridPoint(x: headX - offset, y: centerY)
        }
        heading = .right
        queuedDirection = nil
        score = 0
        didWin = false
        placeFood()
    }

    /// 记录一个待生效的转向，避免同一帧内多次输入互相冲突
    private func queue(_ newDirection: Direction) {
        let reference = queuedDirection ?? heading
        guard newDirection != reference, !newDirection.isOpposite(of: reference) else { return }
        queuedDirection = newDirection
    }

    /// 走一步（由内部计时循环驱动，也方便单元测试直接调用）
    func step() {
        guard state == .running else { return }

        if let next = queuedDirection {
            heading = next
            queuedDirection = nil
        }

        let newHead = snake[0].moved(heading)

        // 撞墙
        guard (0..<Self.columns).contains(newHead.x), (0..<Self.rows).contains(newHead.y) else {
            finish(didWin: false)
            return
        }

        let eating = newHead == food
        // 没有吃到食物时尾巴会同时移走，所以「撞到自己的尾巴」不算死
        let body = eating ? snake : Array(snake.dropLast())
        guard !body.contains(newHead) else {
            finish(didWin: false)
            return
        }

        snake.insert(newHead, at: 0)
        if eating {
            score += Self.pointsPerFood
            if score > bestScore {
                bestScore = score
                UserDefaults.standard.set(bestScore, forKey: Self.bestScoreKey)
            }
            eatCount += 1
            placeFood()
        } else {
            snake.removeLast()
        }
    }

    /// 在一个空位随机放置食物；若没有空位说明已经通关
    private func placeFood() {
        let occupied = Set(snake)
        var freePoints: [GridPoint] = []
        freePoints.reserveCapacity(Self.columns * Self.rows - occupied.count)

        for y in 0..<Self.rows {
            for x in 0..<Self.columns {
                let point = GridPoint(x: x, y: y)
                if !occupied.contains(point) {
                    freePoints.append(point)
                }
            }
        }

        guard let nextFood = freePoints.randomElement() else {
            finish(didWin: true)
            return
        }
        food = nextFood
    }

    private func finish(didWin: Bool) {
        self.didWin = didWin
        state = .gameOver
        crashCount += 1
        stopLoop()
    }

    // MARK: - 计时循环

    private func startLoop() {
        stopLoop()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.tickInterval

                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }

                guard let self else { return }
                guard self.state == .running else { return }
                self.step()
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }
}
