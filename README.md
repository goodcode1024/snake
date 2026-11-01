# MyApp

使用 Zcode 创建。目前是一个 SwiftUI 贪吃蛇小游戏。

## 玩法

- 滑动棋盘，或点按下方的方向键控制小蛇移动。
- 吃到金色食物得 10 分，蛇身变长，移动速度逐渐加快。
- 撞到墙壁或自己的身体即结束；把整个棋盘吃满即为通关。
- 最高分保存在 `UserDefaults` 中。

## 代码结构

- `MyApp/SnakeGame.swift`：游戏规则（网格、转向、食物、碰撞、计分、计时循环）。
- `MyApp/SnakeGameView.swift`：界面（Canvas 棋盘、分数面板、方向键、状态遮罩）。
- `MyApp/ContentView.swift`：应用入口视图，承载游戏画面。

## 构建

由 `.github/workflows/zcode-build.yml` 中的 Zcode Build 工作流构建（scheme 为 `MyApp`，默认 Debug）。
