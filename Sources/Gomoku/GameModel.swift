import SwiftUI
import Combine
import AppKit

// 对战模式：双人同屏热座 / 人机对战
enum GameMode: Equatable {
    case pvp
    case ai
}

// 人机难度：从超简单到超级难
enum AIDifficulty: String, CaseIterable, Identifiable {
    case ultraEasy = "超简单"
    case beginner = "初级"
    case medium = "中等"
    case hard = "困难"
    case unbeatable = "超级难"
    var id: String { rawValue }
}

struct Coord: Hashable {
    let row: Int
    let col: Int
    init(_ row: Int, _ col: Int) { self.row = row; self.col = col }
}

enum Player: CaseIterable {
    case black, white
    var label: String { self == .black ? "黑方" : "白方" }
    var color: Color { self == .black ? .black : .white }
    var next: Player { self == .black ? .white : .black }
}

struct Move: Identifiable {
    let id = UUID()
    let row: Int
    let col: Int
    let player: Player
    func coord() -> String { return "(\(col), \(row))" }
}

final class GameModel: ObservableObject {
    @Published var stones: [Coord: Player] = [:]
    @Published var current: Player = .black
    @Published var moves: [Move] = []
    @Published var winner: Player? = nil
    @Published var winLine: [Coord] = []
    @Published var isDraw: Bool = false
    @Published var blackWins: Int = 0
    @Published var whiteWins: Int = 0
    @Published var blackTime: Double = 0
    @Published var whiteTime: Double = 0
    @Published var firstMoverText: String = ""
    @Published var scale: CGFloat = 1.0
    @Published var soundOn: Bool = true
    @Published var mode: GameMode = .pvp
    @Published var difficulty: AIDifficulty = .medium
    @Published var splitScreen: Bool = false
    @Published var aiHint: Coord? = nil
    @Published var aiHintAuto: Bool = false
    @Published var aiThinking: Bool = false

    private var timer: Timer?
    private var firstIsPlayerA = true

    init() { newGame() }

    var gameOver: Bool { winner != nil || isDraw }

    // 新一局：重置棋局，但保留累计比分
    func newGame() {
        stones = [:]
        current = .black
        moves = []
        winner = nil
        winLine = []
        isDraw = false
        blackTime = 0
        whiteTime = 0
        firstIsPlayerA = Bool.random()
        if mode == .ai {
            // 人机模式：人执黑先手，AI 执白
            firstMoverText = "你（黑方）先手"
        } else {
            firstMoverText = firstIsPlayerA ? "玩家一 执黑先手" : "玩家二 执黑先手"
        }
        aiThinking = false
        aiHint = nil
        startTimer()
    }

    // 双人模式：AI 提示仅服务黑棋方——只在黑棋回合计算黑棋最佳落点，白棋回合清空
    func requestHint() {
        guard mode == .pvp, !gameOver, !aiThinking else { aiHint = nil; return }
        if current == .black {
            aiHint = AIPlayer.findBestMove(stones: stones, ai: .black, difficulty: .hard)
        } else {
            aiHint = nil
        }
    }

    func resetScore() {
        blackWins = 0
        whiteWins = 0
    }

    func place(at row: Int, col: Int) {
        guard !gameOver else { return }
        let key = Coord(row, col)
        guard stones[key] == nil else { return }
        let player = current
        stones[key] = player
        moves.append(Move(row: row, col: col, player: player))
        aiHint = nil
        if let line = winningLine(for: player, at: row, col: col) {
            winner = player
            winLine = line
            if player == .black { blackWins += 1 } else { whiteWins += 1 }
            stopTimer()
            playSound("Glass")   // 获胜提示音
        } else {
            current = player.next
            playSound("Tink")    // 落子嗒声
        }
    }

    // 播放系统音效（异步避免卡 UI）
    private func playSound(_ name: String) {
        guard soundOn else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            NSSound(named: name)?.play()
        }
    }

    // 认输：当前落子方认输，对方获胜并计分
    func resign() {
        guard !gameOver else { return }
        winner = current.next
        winLine = []
        if winner == .black { blackWins += 1 } else { whiteWins += 1 }
        stopTimer()
    }

    // 和棋：直接平局结束，不计入比分
    func declareDraw() {
        guard !gameOver else { return }
        isDraw = true
        stopTimer()
    }

    func undo() {
        guard let last = moves.popLast() else { return }
        stones[Coord(last.row, last.col)] = nil
        winner = nil
        winLine = []
        isDraw = false
        aiHint = nil
        current = last.player
        startTimer()
    }

    // 从棋谱导入对局（复盘用）：重建局面与胜负状态，不动累计比分
    func importMoves(_ imported: [Move], firstMover: String? = nil) {
        stopTimer()
        stones = [:]
        current = .black
        moves = []
        winner = nil
        winLine = []
        isDraw = false
        aiHint = nil
        for m in imported {
            let key = Coord(m.row, m.col)
            guard stones[key] == nil else { continue }
            stones[key] = m.player
            moves.append(m)
        }
        if let last = moves.last {
            if let line = winningLine(for: last.player, at: last.row, col: last.col) {
                winner = last.player
                winLine = line
            } else {
                current = last.player.next
            }
        }
        if let f = firstMover { firstMoverText = f }
        if winner == nil && !isDraw { startTimer() }
    }

    func undoTo(index: Int) {
        guard index >= 0, index <= moves.count else { return }
        while moves.count > index {
            let last = moves.popLast()!
            stones[Coord(last.row, last.col)] = nil
        }
        winner = nil
        winLine = []
        isDraw = false
        aiHint = nil
        current = moves.last?.player.next ?? .black
        startTimer()
    }

    private func winningLine(for player: Player, at row: Int, col: Int) -> [Coord]? {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var line: [Coord] = [Coord(row, col)]
            var r = row + dr, c = col + dc
            while let p = stones[Coord(r, c)], p == player {
                line.append(Coord(r, c)); r += dr; c += dc
            }
            r = row - dr; c = col - dc
            while let p = stones[Coord(r, c)], p == player {
                line.insert(Coord(r, c), at: 0); r -= dr; c -= dc
            }
            if line.count >= 5 { return line }
        }
        return nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, !self.gameOver else { return }
            if self.current == .black { self.blackTime += 0.1 }
            else { self.whiteTime += 0.1 }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func format(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
