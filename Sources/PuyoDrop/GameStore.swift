import AppKit
import SwiftUI

enum BlobColor: String, CaseIterable, Identifiable {
    case coral
    case lemon
    case mint
    case sky
    case grape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coral: "Red"
        case .lemon: "Yellow"
        case .mint: "Green"
        case .sky: "Blue"
        case .grape: "Purple"
        }
    }

    var baseColor: Color {
        switch self {
        case .coral: Color(red: 0.95, green: 0.25, blue: 0.25)
        case .lemon: Color(red: 0.98, green: 0.79, blue: 0.20)
        case .mint: Color(red: 0.12, green: 0.72, blue: 0.42)
        case .sky: Color(red: 0.16, green: 0.55, blue: 0.92)
        case .grape: Color(red: 0.56, green: 0.32, blue: 0.88)
        }
    }
}

enum GameCommand {
    case left
    case right
    case softDrop
    case rotate
    case hardDrop
    case restart
    case pause
}

struct GridPoint: Hashable {
    var row: Int
    var column: Int
}

struct FallingPair {
    var pivot: GridPoint
    var rotation: Int
    var pivotColor: BlobColor
    var satelliteColor: BlobColor

    var cells: [(GridPoint, BlobColor)] {
        let offset = Self.offsets[rotation.modulo(Self.offsets.count)]
        return [
            (pivot, pivotColor),
            (GridPoint(row: pivot.row + offset.row, column: pivot.column + offset.column), satelliteColor),
        ]
    }

    private static let offsets = [
        GridPoint(row: -1, column: 0),
        GridPoint(row: 0, column: 1),
        GridPoint(row: 1, column: 0),
        GridPoint(row: 0, column: -1),
    ]
}

@MainActor
final class GameStore: ObservableObject {
    static let width = 6
    static let height = 12

    @Published private(set) var board: [[BlobColor?]]
    @Published private(set) var currentPair: FallingPair?
    @Published private(set) var nextPair: (BlobColor, BlobColor)
    @Published private(set) var score = 0
    @Published private(set) var chains = 0
    @Published private(set) var bestChain = 0
    @Published private(set) var poppedTotal = 0
    @Published private(set) var isGameOver = false
    @Published var isPaused = false

    private var random = SystemRandomNumberGenerator()

    init() {
        board = Self.emptyBoard()
        nextPair = Self.rollPair(using: &random)
        spawnPair()
    }

    func reset() {
        board = Self.emptyBoard()
        score = 0
        chains = 0
        bestChain = 0
        poppedTotal = 0
        isGameOver = false
        isPaused = false
        nextPair = Self.rollPair(using: &random)
        spawnPair()
    }

    func tick() {
        guard !isPaused, !isGameOver else { return }
        if !moveCurrent(rowDelta: 1, columnDelta: 0) {
            lockCurrentPair()
        }
    }

    func handle(_ command: GameCommand) {
        switch command {
        case .left:
            _ = moveCurrent(rowDelta: 0, columnDelta: -1)
        case .right:
            _ = moveCurrent(rowDelta: 0, columnDelta: 1)
        case .softDrop:
            if !moveCurrent(rowDelta: 1, columnDelta: 0) {
                lockCurrentPair()
            } else {
                score += 1
            }
        case .rotate:
            rotateCurrentPair()
        case .hardDrop:
            hardDrop()
        case .restart:
            reset()
        case .pause:
            guard !isGameOver else { return }
            isPaused.toggle()
        }
    }

    func colorAt(row: Int, column: Int) -> BlobColor? {
        if let fallingColor = currentPair?.cells.first(where: { $0.0.row == row && $0.0.column == column })?.1 {
            return fallingColor
        }
        return board[row][column]
    }

    func ghostCells() -> Set<GridPoint> {
        guard var ghost = currentPair else { return [] }
        while isValid(ghost.moved(rowDelta: 1, columnDelta: 0)) {
            ghost = ghost.moved(rowDelta: 1, columnDelta: 0)
        }
        return Set(ghost.cells.map(\.0))
    }

    private func spawnPair() {
        let pair = nextPair
        currentPair = FallingPair(
            pivot: GridPoint(row: 1, column: Self.width / 2),
            rotation: 0,
            pivotColor: pair.0,
            satelliteColor: pair.1
        )
        nextPair = Self.rollPair(using: &random)

        if let currentPair, !isValid(currentPair) {
            self.currentPair = nil
            isGameOver = true
        }
    }

    @discardableResult
    private func moveCurrent(rowDelta: Int, columnDelta: Int) -> Bool {
        guard let currentPair, !isPaused, !isGameOver else { return false }
        let moved = currentPair.moved(rowDelta: rowDelta, columnDelta: columnDelta)
        guard isValid(moved) else { return false }
        self.currentPair = moved
        return true
    }

    private func rotateCurrentPair() {
        guard let currentPair, !isPaused, !isGameOver else { return }
        let rotated = currentPair.rotatedClockwise()
        for columnKick in [0, -1, 1, -2, 2] {
            let candidate = rotated.moved(rowDelta: 0, columnDelta: columnKick)
            if isValid(candidate) {
                self.currentPair = candidate
                return
            }
        }
    }

    private func hardDrop() {
        guard !isPaused, !isGameOver else { return }
        var dropDistance = 0
        while moveCurrent(rowDelta: 1, columnDelta: 0) {
            dropDistance += 1
        }
        score += dropDistance * 2
        lockCurrentPair()
    }

    private func lockCurrentPair() {
        guard let currentPair else { return }
        for (point, color) in currentPair.cells {
            guard point.row >= 0, point.row < Self.height, point.column >= 0, point.column < Self.width else {
                isGameOver = true
                return
            }
            board[point.row][point.column] = color
        }
        self.currentPair = nil
        resolveChains()
        spawnPair()
    }

    private func resolveChains() {
        chains = 0

        while true {
            let cleared = findClearGroups()
            guard !cleared.isEmpty else { break }
            chains += 1
            bestChain = max(bestChain, chains)

            for point in cleared {
                board[point.row][point.column] = nil
            }

            let popped = cleared.count
            poppedTotal += popped
            score += popped * 10 * max(1, chains * 2)
            applyGravity()
        }
    }

    private func findClearGroups() -> Set<GridPoint> {
        var visited = Set<GridPoint>()
        var cleared = Set<GridPoint>()

        for row in 0..<Self.height {
            for column in 0..<Self.width {
                let start = GridPoint(row: row, column: column)
                guard !visited.contains(start), let color = board[row][column] else { continue }

                var group: [GridPoint] = []
                var queue = [start]
                visited.insert(start)

                while let point = queue.popLast() {
                    group.append(point)

                    for neighbor in neighbors(of: point) {
                        guard !visited.contains(neighbor),
                              board[neighbor.row][neighbor.column] == color else { continue }
                        visited.insert(neighbor)
                        queue.append(neighbor)
                    }
                }

                if group.count >= 4 {
                    cleared.formUnion(group)
                }
            }
        }

        return cleared
    }

    private func applyGravity() {
        for column in 0..<Self.width {
            var stack: [BlobColor] = []
            for row in stride(from: Self.height - 1, through: 0, by: -1) {
                if let color = board[row][column] {
                    stack.append(color)
                }
                board[row][column] = nil
            }

            var writeRow = Self.height - 1
            for color in stack {
                board[writeRow][column] = color
                writeRow -= 1
            }
        }
    }

    private func isValid(_ pair: FallingPair) -> Bool {
        pair.cells.allSatisfy { point, _ in
            point.row >= 0 &&
                point.row < Self.height &&
                point.column >= 0 &&
                point.column < Self.width &&
                board[point.row][point.column] == nil
        }
    }

    private func neighbors(of point: GridPoint) -> [GridPoint] {
        [
            GridPoint(row: point.row - 1, column: point.column),
            GridPoint(row: point.row + 1, column: point.column),
            GridPoint(row: point.row, column: point.column - 1),
            GridPoint(row: point.row, column: point.column + 1),
        ].filter { neighbor in
            neighbor.row >= 0 &&
                neighbor.row < Self.height &&
                neighbor.column >= 0 &&
                neighbor.column < Self.width
        }
    }

    private static func emptyBoard() -> [[BlobColor?]] {
        Array(
            repeating: Array(repeating: nil, count: width),
            count: height
        )
    }

    private static func rollPair(using random: inout SystemRandomNumberGenerator) -> (BlobColor, BlobColor) {
        let colors = BlobColor.allCases
        return (
            colors.randomElement(using: &random) ?? .coral,
            colors.randomElement(using: &random) ?? .sky
        )
    }
}

private extension FallingPair {
    func moved(rowDelta: Int, columnDelta: Int) -> FallingPair {
        var copy = self
        copy.pivot = GridPoint(row: pivot.row + rowDelta, column: pivot.column + columnDelta)
        return copy
    }

    func rotatedClockwise() -> FallingPair {
        var copy = self
        copy.rotation = (rotation + 1).modulo(4)
        return copy
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        ((self % divisor) + divisor) % divisor
    }
}
