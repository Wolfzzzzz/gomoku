import Foundation

// 人机对战 AI：威胁优先级链 + 启发式评分 + 极小极大搜索
// 强度阶梯：超简单(随机) → 初级(必胜点) → 中等(评分+1层) → 困难(威胁链+4层) → 超级难(双杀检测+5层深搜)
//
// 2026-08-29 大修（修复「超级难被新手连招打死」）：
// 1. evaluate 改为「线头法」：每条线段只计一次，消除重复计数导致的评分失真
// 2. 新增「对方一手双杀点」检测：对方落子即形成 ≥2 条强线（活三/冲四/活四）→ 必堵
// 3. 防守优先级严格高于进攻：堵对方五连/活四/双杀/活三 永远先于己方双威胁
//    （旧逻辑里「己方双威胁」排在「堵对方活三」之前，会为了进攻漏防，被声东击西打死）
// 4. 搜索加深：超级难 3 → 5 层、困难 3 → 4 层，能看穿「虚晃一枪 + 连招」类套路
// 5. 极小极大内层用「关键点裁剪」候选（必堵点/活三端/活四端/局部启发），深搜不丢关键防守
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

    // 单点四方向连线评分（重复计数无妨，只用于排序）
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

    // 线段统计（线头法）：返回 player 的所有线段 (count, open, ends)
    // 从每条线的「线头」开始数，保证一条线只统计一次
    static func lineThreats(_ stones: [Coord: Player], for player: Player) -> [(count: Int, open: Int, ends: [Coord])] {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var result: [(count: Int, open: Int, ends: [Coord])] = []
        for (c, p) in stones where p == player {
            for (dr, dc) in dirs {
                let prev = Coord(c.row - dr, c.col - dc)
                if stones[prev] == player { continue }
                var n = 1
                var r = c.row + dr, col = c.col + dc
                while stones[Coord(r, col)] == player { n += 1; r += dr; col += dc }
                let e2 = Coord(r, col)
                let e1 = Coord(c.row - dr, c.col - dc)
                var open = 0
                var ends: [Coord] = []
                if stones[e1] == nil { open += 1; ends.append(e1) }
                if stones[e2] == nil { open += 1; ends.append(e2) }
                result.append((n, open, ends))
            }
        }
        return result
    }

    // 全盘评估（线头法，每条线只计一次）：player 的总威胁分
    static func evaluate(_ stones: [Coord: Player], for player: Player) -> Int {
        var score = 0
        for t in lineThreats(stones, for: player) {
            score += weight(t.count, open: t.open)
        }
        return score
    }

    // 是否存在「活四 / 五连」级必胜威胁
    static func hasWinningThreat(_ stones: [Coord: Player], for player: Player) -> Bool {
        for t in lineThreats(stones, for: player) {
            if t.count >= 5 || (t.count == 4 && t.open == 2) { return true }
        }
        return false
    }

    // player 所有「四连及以上」线的开放端（活四延伸必胜、冲四延伸要堵）
    static func fourEnds(_ stones: [Coord: Player], for player: Player) -> [Coord] {
        var pts: [Coord] = []
        for t in lineThreats(stones, for: player) where t.count >= 4 {
            pts.append(contentsOf: t.ends)
        }
        return pts
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

    // 对方当前棋盘上已有的「活三」开放端：扫描对方所有三连，
    // 若两端皆空（活三），返回两端。活三不堵 → 对方成活四（无解必输）
    static func rivalLiveThreeEnds(_ stones: [Coord: Player], rival: Player) -> Set<Coord> {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var ends = Set<Coord>()
        for (c, p) in stones where p == rival {
            for (dr, dc) in dirs {
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

    // 对方「落子后即成冲四/活四」的高威胁点（含缺口眠三、活三端、冲四延伸）。
    // 这类点不预堵 → 对方下回合成形冲四/活四，局势急转直下。用于提前拆线。
    static func rivalHighThreats(_ stones: [Coord: Player], rival: Player) -> Set<Coord> {
        var pts = Set<Coord>()
        for c in candidatePoints(stones) where stones[c] == nil {
            var s = stones; s[c] = rival
            if lineScore(s, at: c, by: rival) >= 10_000 { pts.insert(c) }
        }
        return pts
    }

    // 对方「一手双杀」点：对方落子后，其下一手能直接成「五连/活四」的杀点 ≥2 个，
    // 或「1 个直接杀点 + 1 个活三起手点」（冲四+活三 = 标准连杀，堵一路必走另一路）。
    // 这类点不堵 → 对方下回合双杀成型，我方一步只能堵一条，必输。
    // 用「杀点数 + 活三起手数」而非「强线数」判定：能识别带缺口的杀棋
    // （例如 3 连 + 1 缺口，下一手即成活四/五连的隐形威胁）。
    static func rivalDoubleThreatPoints(_ stones: [Coord: Player], rival: Player) -> Set<Coord> {
        var pts = Set<Coord>()
        let base = candidatePoints(stones)
        for c in base where stones[c] == nil {
            var s = stones; s[c] = rival
            var kills = 0
            var threes = 0
            for p in candidatePoints(s) where s[p] == nil {
                var s2 = s; s2[p] = rival
                if isWin(s2, at: p, by: rival) || lineScore(s2, at: p, by: rival) >= 100_000 {
                    kills += 1
                } else if isLiveThree(s2, at: p, by: rival) {
                    threes += 1
                }
            }
            if kills >= 2 || (kills >= 1 && threes >= 1) { pts.insert(c) }
        }
        return pts
    }

    // 落 p 后 player 是否在某方向形成「活三」（三连、两端皆空）
    static func isLiveThree(_ stones: [Coord: Player], at p: Coord, by player: Player) -> Bool {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for (dr, dc) in dirs {
            var n = 1
            var open = 0
            var r = p.row + dr, col = p.col + dc
            while stones[Coord(r, col)] == player { n += 1; r += dr; col += dc }
            if stones[Coord(r, col)] == nil { open += 1 }
            r = p.row - dr; col = p.col - dc
            while stones[Coord(r, col)] == player { n += 1; r -= dr; col -= dc }
            if stones[Coord(r, col)] == nil { open += 1 }
            if n == 3 && open == 2 { return true }
        }
        return false
    }

    // 极小极大（含 alpha-beta 剪枝）。顶层调 depth:1 表示"看对方下一步最佳应手"
    // 内层候选用「关键点裁剪」：必堵点 + 活三/活四端 + 局部启发 top，深搜不丢关键防守
    static func minimax(_ stones: [Coord: Player], depth: Int, alpha: Int, beta: Int,
                        ai: Player, maximizing: Bool, threatAware: Bool = false) -> Int {
        if depth == 0 {
            if threatAware {
                if hasWinningThreat(stones, for: ai) { return 2_500_000 }
                if hasWinningThreat(stones, for: ai.next) { return -2_500_000 }
            }
            return evaluate(stones, for: ai) - evaluate(stones, for: ai.next)
        }
        let player = maximizing ? ai : ai.next
        let cands = quickCandidates(stones, for: player).prefix(9)
        if maximizing {
            var best = Int.min
            var a = alpha
            for c in cands {
                var s = stones; s[c] = player
                let v = isWin(s, at: c, by: player)
                    ? 2_000_000
                    : minimax(s, depth: depth - 1, alpha: a, beta: beta, ai: ai, maximizing: false, threatAware: threatAware)
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
                    : minimax(s, depth: depth - 1, alpha: alpha, beta: b, ai: ai, maximizing: true, threatAware: threatAware)
                best = min(best, v)
                b = min(b, best)
                if b <= alpha { break }
            }
            return best
        }
    }

    // 关键点裁剪候选（用于极小极大内层）：按威胁优先级排序，保证防守/进攻要点不丢
    static func quickCandidates(_ stones: [Coord: Player], for player: Player) -> [Coord] {
        let rival = player.next
        var seen = Set<Coord>()
        var pts: [Coord] = []
        func add(_ c: Coord) {
            if stones[c] == nil && !seen.contains(c) { seen.insert(c); pts.append(c) }
        }
        // 0. 己方五连点（直接赢）
        for c in candidatePoints(stones) {
            var s = stones; s[c] = player
            if isWin(s, at: c, by: player) { add(c) }
        }
        // 1. 对方五连点（必堵）
        for c in candidatePoints(stones) {
            var s = stones; s[c] = rival
            if isWin(s, at: c, by: rival) { add(c) }
        }
        // 2. 对方活四/冲四延伸端
        for t in lineThreats(stones, for: rival) where t.count == 4 {
            for e in t.ends { add(e) }
        }
        // 3. 对方活三开放端
        for e in rivalLiveThreeEnds(stones, rival: rival) { add(e) }
        // 4. 己方活四延伸端
        for t in lineThreats(stones, for: player) where t.count >= 4 {
            for e in t.ends { add(e) }
        }
        // 5. 局部启发 top 6（进攻 + 防守×2）
        var scored: [(Coord, Int)] = []
        for c in candidatePoints(stones) {
            var s = stones; s[c] = player
            let atk = quickLine(s, at: c, by: player)
            var s2 = stones; s2[c] = rival
            let def = quickLine(s2, at: c, by: rival)
            scored.append((c, atk + def * 2))
        }
        scored.sort { $0.1 > $1.1 }
        for (c, _) in scored.prefix(6) { add(c) }
        return pts
    }

    // 落点局部最强威胁（只扫 4 方向，比全盘 evaluate 快）
    static func quickLine(_ stones: [Coord: Player], at c: Coord, by player: Player) -> Int {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var best = 0
        for (dr, dc) in dirs {
            var n = 1
            var open = 0
            var r = c.row + dr, col = c.col + dc
            while stones[Coord(r, col)] == player { n += 1; r += dr; col += dc }
            if stones[Coord(r, col)] == nil { open += 1 }
            r = c.row - dr; col = c.col - dc
            while stones[Coord(r, col)] == player { n += 1; r -= dr; col -= dc }
            if stones[Coord(r, col)] == nil { open += 1 }
            best = max(best, weight(n, open: open))
        }
        return best
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
            // 中等：启发式评分 + 看对方一步 + 堵已成活三/活四（不预堵缺口，保持原阶梯强度）
            return search(stones: stones, ai: ai, depth: 1, topN: 12, doubleThreatFirst: false,
                          alwaysBlock: true)

        case .hard:
            // 困难：双杀点必堵 + 对方活三/活四硬堵 + 缺口预堵 + 深度 4 搜索（带活四感知）
            return search(stones: stones, ai: ai, depth: 4, topN: 10, doubleThreatFirst: true,
                          alwaysBlock: true, blockGaps: true, threatAware: true)

        case .unbeatable:
            // 超级难：必胜/必堵/双杀必堵/活三硬堵/缺口预堵 + 深度 5 宽搜索 + 开局定式
            if stones.count == 1 {
                // 后手开局定式：斜角/正交呼应天元，占据与黑方相邻的强位
                let first = stones.keys.first!
                let cand = [Coord(first.row + 1, first.col + 1), Coord(first.row - 1, first.col - 1),
                            Coord(first.row + 1, first.col - 1), Coord(first.row - 1, first.col + 1),
                            Coord(first.row, first.col + 1), Coord(first.row + 1, first.col),
                            Coord(first.row, first.col - 1), Coord(first.row - 1, first.col)]
                for c in cand where stones[c] == nil { return c }
            }
            return search(stones: stones, ai: ai, depth: 5, topN: 12, doubleThreatFirst: true,
                          alwaysBlock: true, blockGaps: true, threatAware: true)
        }
    }

    // 通用搜索：威胁优先级链 = 己方五连 → 堵对方五连 → 堵对方活四 → 己方活四 → 堵对方双杀
    //                                → 堵对方活三 → 己方双威胁 → 预堵对方冲四 → minimax 深搜
    static func search(stones: [Coord: Player], ai: Player, depth: Int, topN: Int,
                       doubleThreatFirst: Bool, alwaysBlock: Bool = false,
                       blockGaps: Bool = false, threatAware: Bool = false) -> Coord? {
        let rival = ai.next
        let cands = rankedCandidates(stones, for: ai)

        // 1. 己方直接五连，立即赢
        for c in cands {
            var s = stones; s[c] = ai
            if isWin(s, at: c, by: ai) { return c }
        }
        // 2. 对方有直接五连 → 必堵（挑进攻性最强的堵点）
        var blocks: [Coord] = []
        for c in cands {
            var s = stones; s[c] = rival
            if isWin(s, at: c, by: rival) { blocks.append(c) }
        }
        if !blocks.isEmpty {
            return blocks.max { attackScore(stones, at: $0, by: ai) < attackScore(stones, at: $1, by: ai) }
        }
        // 3. 对方已成活四 → 堵其延伸端（争抢唯一生机，挑能顺便反攻的端）
        if hasWinningThreat(stones, for: rival) {
            let ends = fourEnds(stones, for: rival)
            if !ends.isEmpty {
                return ends.max { attackScore(stones, at: $0, by: ai) < attackScore(stones, at: $1, by: ai) }
            }
        }
        // 4. 己方已成活四 → 延伸必赢
        if hasWinningThreat(stones, for: ai) {
            if let e = fourEnds(stones, for: ai).first { return e }
        }
        // 5. 对方「一手双杀」点必堵（防一手成型双杀）—— 高难度专用
        if doubleThreatFirst || threatAware {
            let pts = rivalDoubleThreatPoints(stones, rival: rival)
            if !pts.isEmpty {
                // 选「拆线效果最好」的堵点：落子后对方剩余双杀点最少、剩余总威胁最低、进攻价值最高
                var best: Coord? = nil
                var bestLeft = Int.max
                var bestThreat = Int.max
                var bestAtk = -1
                for c in pts {
                    var s = stones; s[c] = ai
                    let left = rivalDoubleThreatPoints(s, rival: rival).count
                    let threat = evaluate(s, for: rival)
                    let atk = attackScore(stones, at: c, by: ai)
                    if left < bestLeft || (left == bestLeft && threat < bestThreat)
                        || (left == bestLeft && threat == bestThreat && atk > bestAtk) {
                        bestLeft = left; bestThreat = threat; bestAtk = atk; best = c
                    }
                }
                if let b = best { return b }
            }
        }
        // 6. 对方已成活三：必堵其开放端（否则对方成活四无解）—— 中等及以上
        if alwaysBlock {
            let ends = rivalLiveThreeEnds(stones, rival: rival)
            if !ends.isEmpty {
                return ends.max { attackScore(stones, at: $0, by: ai) < attackScore(stones, at: $1, by: ai) }
            }
        }
        // 7. 己方双威胁必胜形（防守任务清空后，下完对方堵不完）
        if doubleThreatFirst {
            for c in cands {
                var s = stones; s[c] = ai
                if doubleThreat(s, at: c, by: ai) { return c }
            }
        }
        // 8. 对方高威胁点（缺口眠三/冲四延伸）预堵：提前拆线 —— 仅困难/超级难
        if blockGaps {
            let threats = rivalHighThreats(stones, rival: rival)
            if !threats.isEmpty {
                return threats.max { attackScore(stones, at: $0, by: ai) < attackScore(stones, at: $1, by: ai) }
            }
        }
        // 9. 对 Top N 候选做 minimax 深度搜索
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
