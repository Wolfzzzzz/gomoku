import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = GameModel()
    @State private var monitor: Any? = nil
    @State private var lastScale: CGFloat = 1
    @State private var pan: CGPoint = .zero
    @State private var isDragging: Bool = false
    @State private var importAlert: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            boardArea
        }
        .onAppear { addMonitor() }
        .onDisappear { removeMonitor() }
        .alert("导入棋谱", isPresented: Binding(get: { importAlert != nil },
                                                set: { if !$0 { importAlert = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importAlert ?? "")
        }
    }

    // 主棋盘区：分屏对战（双人隔开）或普通单棋盘
    @ViewBuilder
    var boardArea: some View {
        if model.mode == .pvp && model.splitScreen {
            HStack(spacing: 0) {
                splitBoard(side: .black, title: "玩家一（黑方）")
                splitDivider
                splitBoard(side: .white, title: "玩家二（白方）")
            }
            .onChange(of: model.mode) { _, _ in
                model.newGame()
                pan = .zero
                model.scale = 1
                maybeAiMove()
            }
            .onChange(of: model.current) { _, _ in
                maybeAiMove()
                refreshAutoHint()
            }
        } else {
            HStack(spacing: 0) {
                BoardView(model: model,
                          onPlace: { r, c in
                              // 人机模式：AI 思考中或轮到 AI 时禁止人类落子
                              guard !model.aiThinking,
                                    !(model.mode == .ai && model.current == .white) else { return }
                              model.place(at: r, col: c)
                          },
                          pan: $pan,
                          isDragging: $isDragging,
                          hintVisible: model.aiHint != nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(magnify)
                    .background(Color(NSColor.windowBackgroundColor))
                SidePanel(model: model)
            }
            .onChange(of: model.mode) { _, _ in
                // 切换模式即开新局
                model.newGame()
                pan = .zero
                model.scale = 1
                maybeAiMove()
            }
            .onChange(of: model.current) { _, _ in
                // 覆盖所有"轮到 AI"的路径（落子/悔棋/棋谱回溯）
                maybeAiMove()
            }
        }
    }

    // 分屏对战：黑/白各占半边，棋盘数据完全同步，AI 提示只显示在本侧屏幕
    @ViewBuilder
    func splitBoard(side: Player, title: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(side.color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.gray))
                Text(title).font(.caption).foregroundColor(.secondary)
                if model.current == side && !model.gameOver {
                    Text("该你下").font(.caption2).bold().foregroundColor(.orange)
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            BoardView(model: model,
                      onPlace: { r, c in
                          guard !model.gameOver else { return }
                          model.place(at: r, col: c)
                      },
                      pan: $pan,
                      isDragging: $isDragging,
                      hintVisible: model.splitScreen && model.aiHint != nil && side == .black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(magnify)
        }
    }

    // 中间屏风隔条：留一条深色竖线，方便放纸挡住对方视线
    var splitDivider: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.45))
            Text("屏风").font(.caption2).foregroundColor(.white.opacity(0.75))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24)
        .frame(maxHeight: .infinity)
    }

    var magnify: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                let d = v / lastScale
                model.scale = min(max(model.scale * d, 0.3), 5)
                lastScale = v
            }
            .onEnded { _ in lastScale = 1 }
    }

    var toolbar: some View {
        HStack {
            Picker("模式", selection: $model.mode) {
                Text("双人对战").tag(GameMode.pvp)
                Text("人机对战").tag(GameMode.ai)
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .help("双人同屏轮流下，或与 AI 对战")

            if model.mode == .ai {
                Picker("难度", selection: $model.difficulty) {
                    ForEach(AIDifficulty.allCases) { d in Text(d.rawValue).tag(d) }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
                .help("AI 强度：超简单~超级难")
            }
            if model.mode == .pvp {
                Toggle(isOn: $model.splitScreen) {
                    Label("分屏", systemImage: "rectangle.split.2x1")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("两人各看半边，中间可放纸，互看不到对方屏幕")
                Toggle(isOn: Binding(get: { model.aiHintAuto },
                                      set: { on in
                                          model.aiHintAuto = on
                                          if on {
                                              // 打开后立即为当前回合方算一次提示
                                              if model.mode == .pvp && !model.gameOver {
                                                  model.requestHint()
                                              }
                                          } else {
                                              model.aiHint = nil
                                          }
                                      })) {
                    Label("AI 提示", systemImage: "lightbulb")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.gameOver)
                .help("打开后自动为黑棋方显示 AI 推荐落点，对面落完自动更新（仅黑棋方屏幕可见，白棋看不到）")
            }

            Button { model.newGame(); maybeAiMove() } label: { Label("新一局", systemImage: "plus.circle") }
            Button { undoForMode() } label: { Label("悔棋", systemImage: "arrow.uturn.backward") }
                .disabled(model.moves.isEmpty || model.gameOver)
            Button { model.newGame(); maybeAiMove() } label: { Label("重开", systemImage: "arrow.clockwise") }
            Button { model.resign() } label: { Label("认输", systemImage: "flag") }
                .disabled(model.gameOver)
            Button { model.declareDraw() } label: { Label("和棋", systemImage: "hand.raised") }
                .disabled(model.gameOver)
            Button { model.resetScore() } label: { Label("清零比分", systemImage: "gobackward") }
                .help("重置累计比分")

            Spacer()

            Button { model.soundOn.toggle() } label: { Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill") }
                .help("音效开关")
            Button { importGame() } label: { Label("导入棋谱", systemImage: "square.and.arrow.up") }
                .help("从文本文件导入棋谱复盘")
            Button { exportGame() } label: { Label("保存棋谱", systemImage: "square.and.arrow.down") }
                .help("导出棋谱为文本文件")
            Button { pan = .zero; model.scale = 1 } label: { Label("归位", systemImage: "scope") }
                .help("回到原点并恢复 100%")

            Spacer()

            Button { model.scale = max(0.3, model.scale - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
            Slider(value: $model.scale, in: 0.3...5).frame(width: 120)
            Button { model.scale = min(5, model.scale + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
            Text("\(Int(model.scale * 100))%").frame(width: 44)
        }
        .padding(8)
        .background(.ultraThinMaterial)
    }

    // 导出棋谱为文本文件（NSSavePanel）
    func exportGame() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "gomoku-record.txt"
        panel.title = "保存棋谱"
        if panel.runModal() == .OK, let url = panel.url {
            var text = "五子棋棋谱\n"
            text += "比分  黑 \(model.blackWins) : \(model.whiteWins) 白\n"
            text += "先手  \(model.firstMoverText)\n"
            text += "步数   \(model.moves.count)\n"
            for (i, m) in model.moves.enumerated() {
                text += "\(i + 1). \(m.player.label) \(m.coord())\n"
            }
            if let w = model.winner { text += "结果  \(w.label) 获胜\n" }
            else if model.isDraw { text += "结果  和棋\n" }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // 导入棋谱（NSOpenPanel）：解析导出的 txt，重建局面并居中视图
    func importGame() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.title = "导入棋谱"
        guard panel.runModal() == .OK, let url = panel.url,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        var imported: [Move] = []
        var firstMover: String? = nil
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("先手") { firstMover = line; continue }
            // 棋谱行格式： "1. 黑方 (3, -2)"（坐标为 列, 行）
            guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"),
                  open < close else { continue }
            let coordStr = line[line.index(after: open)..<close]
            let nums = coordStr.split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count == 2 else { continue }
            let player: Player = line.contains("黑方") ? .black : .white
            imported.append(Move(row: nums[1], col: nums[0], player: player))
        }
        guard !imported.isEmpty else {
            importAlert = "没有解析到有效棋步，请确认选择的是五子棋导出的棋谱文件。"
            return
        }

        model.importMoves(imported, firstMover: firstMover)
        // 视图自动居中到棋局包围盒中心，方便直接看到棋盘
        let rows = imported.map { $0.row }
        let cols = imported.map { $0.col }
        pan = CGPoint(x: CGFloat((cols.min()! + cols.max()!) / 2),
                      y: CGFloat((rows.min()! + rows.max()!) / 2))
        importAlert = "已导入 \(imported.count) 步棋，局面已恢复。\(model.winner.map { "\($0.label) 获胜。" } ?? "轮到 \(model.current.label)。")"
        maybeAiMove()
    }

    // 人机模式：轮到 AI（白方）且未终局时，后台算棋、短暂延迟后落子
    func maybeAiMove() {
        guard model.mode == .ai, model.current == .white, !model.gameOver, !model.aiThinking else { return }
        model.aiThinking = true
        let snapshot = model.stones   // 值类型快照，后台线程安全
        DispatchQueue.global(qos: .userInitiated).async {
            let move = AIPlayer.findBestMove(stones: snapshot, ai: .white, difficulty: model.difficulty)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                model.aiThinking = false
                if let m = move, !model.gameOver { model.place(at: m.row, col: m.col) }
            }
        }
    }

    // 自动 AI 提示：双人模式开启「AI 提示」开关后，每次轮到自己自动重算，不用手动按
    func refreshAutoHint() {
        guard model.aiHintAuto, model.mode == .pvp else { return }
        model.requestHint()
    }

    // 人机模式悔棋：一次撤掉 AI + 人类两步，回到人类重新下
    func undoForMode() {
        guard !model.aiThinking else { return }
        model.undo()
        if model.mode == .ai && model.current == .white { model.undo() }
    }

    func addMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.modifierFlags.contains(.command) {
                let d = event.scrollingDeltaY
                model.scale = min(max(model.scale * (1 + d * 0.005), 0.3), 5)
                return nil
            }
            return event
        }
    }

    func removeMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
