import SwiftUI
import Combine

struct SnakeGameView: View {
    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    private enum Direction {
        case up, down, left, right
    }

    @State private var snake: [Cell] = [Cell(x: 8, y: 7), Cell(x: 7, y: 7), Cell(x: 6, y: 7)]
    @State private var food = Cell(x: 16, y: 7)
    @State private var direction: Direction = .right
    @State private var queuedDirection: Direction = .right
    @State private var score = 0
    @AppStorage("arcade.snake.best") private var best = 0
    @State private var isPaused = false
    @State private var isGameOver = false
    @State private var didWin = false
    @FocusState private var restartFocused: Bool

    private let columns = 24
    private let rows = 14
    private let timer = Timer.publish(every: 0.13, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let boardSize = boardDimensions(in: proxy.size)
            let cellSize = min(boardSize.width / CGFloat(columns), boardSize.height / CGFloat(rows))
            let actualSize = CGSize(width: cellSize * CGFloat(columns), height: cellSize * CGFloat(rows))

            ZStack {
                Color.black.ignoresSafeArea()

                VStack {
                    HStack {
                        Text("SNAKE")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                        Spacer()
                        Text("Score \(score)")
                            .font(.title2.bold())
                        Text("Best \(best)")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 55)
                    .padding(.top, 25)
                    Spacer()
                }

                Canvas { context, _ in
                    let boardRect = CGRect(
                        x: (proxy.size.width - actualSize.width) / 2,
                        y: (proxy.size.height - actualSize.height) / 2 + 20,
                        width: actualSize.width,
                        height: actualSize.height
                    )

                    context.fill(Path(roundedRect: boardRect, cornerRadius: 18), with: .color(Color.white.opacity(0.06)))

                    for cell in snake {
                        let rect = cellRect(cell, boardRect: boardRect, cellSize: cellSize).insetBy(dx: 2, dy: 2)
                        context.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(.green))
                    }

                    if !didWin {
                        let foodRect = cellRect(food, boardRect: boardRect, cellSize: cellSize).insetBy(dx: 5, dy: 5)
                        context.fill(Path(ellipseIn: foodRect), with: .color(.red))
                    }
                }

                if isGameOver {
                    endOverlay
                } else if isPaused {
                    pauseOverlay
                }
            }
            .focusable(!isGameOver)
            .onMoveCommand { command in
                guard !isPaused, !isGameOver else { return }
                switch command {
                case .up where direction != .down: queuedDirection = .up
                case .down where direction != .up: queuedDirection = .down
                case .left where direction != .right: queuedDirection = .left
                case .right where direction != .left: queuedDirection = .right
                default: break
                }
            }
            .onPlayPauseCommand {
                guard !isGameOver else { return }
                isPaused.toggle()
            }
            .onReceive(timer) { _ in
                guard !isPaused, !isGameOver else { return }
                advance()
            }
            .onChange(of: isGameOver) { newValue in
                if newValue {
                    restartFocused = true
                }
            }
        }
        .navigationTitle("Snake")
    }

    private func boardDimensions(in size: CGSize) -> CGSize {
        CGSize(width: max(600, size.width - 180), height: max(350, size.height - 210))
    }

    private func cellRect(_ cell: Cell, boardRect: CGRect, cellSize: CGFloat) -> CGRect {
        CGRect(
            x: boardRect.minX + CGFloat(cell.x) * cellSize,
            y: boardRect.minY + CGFloat(cell.y) * cellSize,
            width: cellSize,
            height: cellSize
        )
    }

    private func advance() {
        direction = queuedDirection
        guard let head = snake.first else {
            reset()
            return
        }

        var next = head
        switch direction {
        case .up: next = Cell(x: head.x, y: head.y - 1)
        case .down: next = Cell(x: head.x, y: head.y + 1)
        case .left: next = Cell(x: head.x - 1, y: head.y)
        case .right: next = Cell(x: head.x + 1, y: head.y)
        }

        let hitWall = next.x < 0 || next.x >= columns || next.y < 0 || next.y >= rows
        let isEating = next == food
        // Moving into the cell the tail is vacating is legal when not eating.
        let collisionBody = isEating ? snake : Array(snake.dropLast())
        let hitSelf = collisionBody.contains(next)

        if hitWall || hitSelf {
            finishGame(won: false)
            return
        }

        snake.insert(next, at: 0)

        if isEating {
            score += 1
            best = max(best, score)
            if !placeFood() {
                finishGame(won: true)
            }
        } else {
            snake.removeLast()
        }
    }

    @discardableResult
    private func placeFood() -> Bool {
        let occupied = Set(snake)
        let available = (0..<columns).flatMap { x in
            (0..<rows).map { Cell(x: x, y: $0) }
        }.filter { !occupied.contains($0) }

        guard let nextFood = available.randomElement() else { return false }
        food = nextFood
        return true
    }

    private func finishGame(won: Bool) {
        best = max(best, score)
        didWin = won
        isPaused = false
        isGameOver = true
    }

    private func reset() {
        snake = [Cell(x: 8, y: 7), Cell(x: 7, y: 7), Cell(x: 6, y: 7)]
        direction = .right
        queuedDirection = .right
        score = 0
        isPaused = false
        isGameOver = false
        didWin = false
        restartFocused = false
        _ = placeFood()
    }

    private var pauseOverlay: some View {
        VStack(spacing: 14) {
            Text("PAUSED")
                .font(.system(size: 58, weight: .black, design: .rounded))
            Text("Press Play/Pause to continue")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private var endOverlay: some View {
        VStack(spacing: 18) {
            Text(didWin ? "YOU WIN" : "GAME OVER")
                .font(.system(size: 58, weight: .black, design: .rounded))
            Text("Score \(score) · Best \(best)")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Play Again") {
                reset()
            }
            .buttonStyle(.borderedProminent)
            .focused($restartFocused)
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}
