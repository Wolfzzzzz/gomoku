import Foundation

// 人机对战 AI：启发式评分 + 两层极小极大搜索
// - 候选点只取已有棋子周围 2 格（无限棋盘裁剪，保证速度）
// - 每步综合「进攻分 + 防守分×2」，防守优先
// - 顶层对 Top 12 候选做 1 层搜索（看对方最佳应手）
struct AIPlayer {

    // 候选点：所有已有棋子周围 2 格内的空点
    static func candidatePoints(_ stones: [Coord: Player]) -> [Coord] {
        var set = Set<Coord>()
        for key in stones.keys {
            for dr in -2...2 {
                for dc in -2...2 {
                    let c = Coord(key.row + dr, key.col + dc)
                    if stones[c] == nil { set.insert(c) }
                }
            }
        }
        return Array(set)
    }

    // 在 c 放 player 后是否直接连成五子
    static func isWin(_ stones: [Coord: Player], at c: Coord, by player: Player) -> Bool {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var n = 1
            var r = c.row + dr, col = c.col + dc
            while stones[Coord(r, col)] == player { n += 1; r += dr; col += dc }
            r = c.row - dr; col = c.col - dc
            while stones[Coord(r, col)] == player { n += 1; r -= dr; col -= dc }
            if n >= 5 { return true }
        }
        return false
    }

    // 单个棋子四个方向的连线评分（重复计数无妨，只用于排序）
    static func lineScore(_ stones: [Coord: Player], at c: Coord, by player: Player) -> Int {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var total = 0
        for (dr, dc) in dirs {
            var n = 1
            var open = 0
            var r = c.row + dr, col = c.col + dc
            while stones[Coord(r, col)] == player { n += 1; r += dr; col += dc }
            if stones[Coord(r, col)] == nil { open += 1 }
            r = c.row - dr; col = c.col - dc
            while stones[Coord(r, col)] == player { n += 1; r -= dr; col -= dc }
            if stones[Coord(r, col)] == nil { open += 1 }
            total += weight(n, open: open)
        }
        return total
    }

    // 连线权重：连子越长、两端越开放，威胁越大
    static func weight(_ n: Int, open: Int) -> Int {
        if n >= 5 { return 1_000_000 }
        switch (n, open) {
        case (4, 2): return 100_000   // 活四
        case (4, 1): return 10_000    // 冲四
        case (3, 2): return 8_000     // 活三
        case (3, 1): return 800       // 眠三
        case (2, 2): return 500       // 活二
        case (2, 1): return 50        // 眠二
        case (1, _): return 5
        default: return 0
        }
    }

    // 全盘评估：player 的总威胁分
    static func evaluate(_ stones: [Coord: Player], for player: Player) -> Int {
        var score = 0
        for (c, p) in stones where p == player {
            score += lineScore(stones, at: c, by: player)
        }
        return score
    }

    // 候选点按「进攻 + 防守×2」排序（防守优先，先堵对方再发展自己）
    static func rankedCandidates(_ stones: [Coord: Player], for player: Player) -> [Coord] {
        let rival = player.next
        var scored: [(Coord, Int)] = []
        for c in candidatePoints(stones) {
            var s = stones; s[c] = player
            let attack = evaluate(s, for: player)
            var s2 = stones; s2[c] = rival
            let defend = evaluate(s2, for: rival)
            scored.append((c, attack + defend * 2))
        }
        scored.sort { $0.1 > $1.1 }
        return scored.map { $0.0 }
    }

    // 是否有「活四/五连」级别威胁（活四无解，等于必胜/必败）
    static func hasWinningThreat(_ stones: [Coord: Player], for player: Player) -> Bool {
        for (c, p) in stones where p == player {
            if lineScore(stones, at: c, by: player) >= 100_000 { return true }
        }
        return false
    }

    // 对方当前棋盘上已有的「活三」开放端：扫描对方所有三连，
    // 若两端皆空（活三），返回两端。活三不堵 → 对方成活四（无解必输）
    static func rivalLiveThreeEnds(_ stones: [Coord: Player], rival: Player) -> Set<Coord> {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var ends = Set<Coord>()
        for (c, p) in stones where p == rival {
            for (dr, dc) in dirs {
                // 只统计每条线的线头，避免重复计数
                let prev = Coord(c.row - dr, c.col - dc)
                if stones[prev] == rival { continue }
                var n = 1
                var r = c.row + dr, col = c.col + dc
                while stones[Coord(r, col)] == rival { n += 1; r += dr; col += dc }
                if n == 3 {
                    let e1 = Coord(c.row - dr, c.col - dc)
                    let e2 = Coord(r, col)
                    if stones[e1] == nil && stones[e2] == nil {
                        ends.insert(e1); ends.insert(e2)
                    }
                }
            }
        }
        return ends
    }

    // 极小极大（含 alpha-beta 剪枝）。顶层调 depth:1 表示"看对方下一步最佳应手"
    static func minimax(_ stones: [Coord: Player], depth: Int, alpha: Int, beta: Int,
                        ai: Player, maximizing: Bool, threatAware: Bool = false) -> Int {
        if depth == 0 {
            // 活四/五连感知：一方成活四即锁定胜局（这是"看穿活三"的关键，仅高难度启用）
            if threatAware {
                if hasWinningThreat(stones, for: ai) { return 2_500_000 }
                if hasWinningThreat(stones, for: ai.next) { return -2_500_000 }
            }
            return evaluate(stones, for: ai) - evaluate(stones, for: ai.next)
        }
        let player = maximizing ? ai : ai.next
        let cands = rankedCandidates(stones, for: player).prefix(10)
        if maximizing {
            var best = Int.min
            var a = alpha
            for c in cands {
                var s = stones; s[c] = player
                let v = isWin(s, at: c, by: player)
                    ? 2_000_000
                    : minimax(s, depth: depth - 1, alpha: a, beta: beta, ai: ai, maximizing: false)
                best = max(best, v)
                a = max(a, best)
                if beta <= a { break }
            }
            return best
        } else {
            var best = Int.max
            var b = beta
            for c in cands {
                var s = stones; s[c] = player
                let v = isWin(s, at: c, by: player)
                    ? -2_000_000
                    : minimax(s, depth: depth - 1, alpha: alpha, beta: b, ai: ai, maximizing: true)
                best = min(best, v)
                b = min(b, best)
                if b <= alpha { break }
            }
            return best
        }
    }

    // 单点进攻分：假设该点已放 player 的子，看它能形成多大威胁
    static func attackScore(_ stones: [Coord: Player], at c: Coord, by player: Player) -> Int {
        var s = stones; s[c] = player
        return lineScore(s, at: c, by: player)
    }

    // 双威胁检测：在 c 落子后形成 ≥2 个「活三及以上」方向（双三/冲四+活三/双四）
    // 对方一步只能堵一个，属于必胜形
    static func doubleThreat(_ stones: [Coord: Player], at c: Coord, by player: Player) -> Bool {
        var s = stones; s[c] = player
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var strong = 0
        for (dr, dc) in dirs {
            var n = 1
            var open = 0
            var r = c.row + dr, col = c.col + dc
            while s[Coord(r, col)] == player { n += 1; r += dr; col += dc }
            if s[Coord(r, col)] == nil { open += 1 }
            r = c.row - dr; col = c.col - dc
            while s[Coord(r, col)] == player { n += 1; r -= dr; col -= dc }
            if s[Coord(r, col)] == nil { open += 1 }
            if weight(n, open: open) >= 8_000 { strong += 1 }
        }
        return strong >= 2
    }

    // 对外入口：按难度返回 AI 的最佳落点
    static func findBestMove(stones: [Coord: Player], ai: Player,
                             difficulty: AIDifficulty = .medium) -> Coord? {
        guard !stones.isEmpty else { return Coord(0, 0) }  // 空盘下原点
        let cands = candidatePoints(stones)
        switch difficulty {
        case .ultraEasy:
            // 超简单：纯随机，不看局面
            return cands.randomElement()

        case .beginner:
            // 初级：只会吃必胜点、堵对方冲四，其余随机
            for c in cands {
                var s = stones; s[c] = ai
                if isWin(s, at: c, by: ai) { return c }
            }
            for c in cands {
                var s = stones; s[c] = ai.next
                if isWin(s, at: c, by: ai.next) { return c }
            }
            return cands.randomElement()

        case .medium:
            // 中等：启发式评分 + 看对方一步（原实现，保持干脆利落）
            return search(stones: stones, ai: ai, depth: 1, topN: 12, doubleThreatFirst: false)

        case .hard:
            // 困难：双威胁识别 + 对方活三硬堵 + 深度 3 搜索（带活四感知）
            return search(stones: stones, ai: ai, depth: 3, topN: 10, doubleThreatFirst: true,
                          alwaysBlock: true, threatAware: true)

        case .unbeatable:
            // 超级难：必胜/必堵/双威胁/活三硬堵优先级 + 深度 3 宽搜索
            return search(stones: stones, ai: ai, depth: 3, topN: 14, doubleThreatFirst: true,
                          alwaysBlock: true, threatAware: true)
        }
    }

    // 通用搜索：优先级 = 己方五连 → 堵对方五连 → 己方双威胁 → 堵对方活三 → minimax
    static func search(stones: [Coord: Player], ai: Player, depth: Int, topN: Int,
                       doubleThreatFirst: Bool, alwaysBlock: Bool = false,
                       threatAware: Bool = false) -> Coord? {
        let rival = ai.next
        let cands = rankedCandidates(stones, for: ai)

        // 1. 己方直接五连，立即赢
        for c in cands {
            var s = stones; s[c] = ai
            if isWin(s, at: c, by: ai) { return c }
        }
        // 2. 对方有直接五连 → 必堵（超级难时挑进攻性最强的堵点）
        var blocks: [Coord] = []
        for c in cands {
            var s = stones; s[c] = rival
            if isWin(s, at: c, by: rival) { blocks.append(c) }
        }
        if !blocks.isEmpty {
            if alwaysBlock {
                return blocks.max { attackScore(stones, at: $0, by: ai) < attackScore(stones, at: $1, by: ai) }
            }
            return blocks.first
        }
        // 3. 己方双威胁必胜形（下完对方堵不完）
        if doubleThreatFirst {
            for c in cands {
                var s = stones; s[c] = ai
                if doubleThreat(s, at: c, by: ai) { return c }
            }
        }
        // 4. 对方活三：若无先手棋，必须堵其开放端，否则对方成活四（无解必输）
        if alwaysBlock {
            let ends = rivalLiveThreeEnds(stones, rival: rival)
            if !ends.isEmpty {
                return ends.max { attackScore(stones, at: $0, by: ai) < attackScore(stones, at: $1, by: ai) }
            }
        }
        // 5. 对 Top N 候选做 minimax 深度搜索
        var best: Coord? = nil
        var bestVal = Int.min
        for c in cands.prefix(topN) {
            var s = stones; s[c] = ai
            let v = minimax(s, depth: depth, alpha: Int.min, beta: Int.max,
                            ai: ai, maximizing: false, threatAware: threatAware)
            if v > bestVal { bestVal = v; best = c }
        }
        return best ?? cands.first
    }
}
