import SwiftUI

struct BoardView: View {
    @ObservedObject var model: GameModel
    var onPlace: (Int, Int) -> Void
    @Binding var pan: CGPoint
    @Binding var isDragging: Bool
    var hintVisible: Bool = false

    @State private var hover: (Int, Int)? = nil
    @State private var dragStart: CGPoint? = nil
    @State private var panStart: CGPoint? = nil
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0

    private let baseCell: CGFloat = 44

    func cellSize(in size: CGSize) -> CGFloat { baseCell * model.scale }

    func boardCoord(from point: CGPoint, in size: CGSize, cell: CGFloat) -> (Int, Int) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let col = ((point.x - center.x) / cell + pan.x).rounded()
        let row = ((point.y - center.y) / cell + pan.y).rounded()
        return (Int(row), Int(col))
    }
    func screenPoint(of row: Int, _ col: Int, in size: CGSize, cell: CGFloat) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: center.x + (CGFloat(col) - pan.x) * cell,
                       y: center.y + (CGFloat(row) - pan.y) * cell)
    }

    var body: some View {
        GeometryReader { geo in
            let cell = cellSize(in: geo.size)
            ZStack {
                Canvas { ctx, size in
                    let bg = Color(red: 0.86, green: 0.66, blue: 0.42)
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let minCol = Int(floor((0 - center.x) / cell + pan.x)) - 1
                    let maxCol = Int(ceil((size.width - center.x) / cell + pan.x)) + 1
                    let minRow = Int(floor((0 - center.y) / cell + pan.y)) - 1
                    let maxRow = Int(ceil((size.height - center.y) / cell + pan.y)) + 1

                    var grid = Path()
                    for c in minCol...maxCol {
                        let x = center.x + (CGFloat(c) - pan.x) * cell
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for r in minRow...maxRow {
                        let y = center.y + (CGFloat(r) - pan.y) * cell
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    ctx.stroke(grid, with: .color(.black.opacity(0.85)), lineWidth: 1)

                    // 坐标标尺：顶部列号、左侧行号
                    let ruler = Color.black.opacity(0.55)
                    for c in minCol...maxCol {
                        let x = center.x + (CGFloat(c) - pan.x) * cell
                        ctx.draw(Text("\(c)").font(.system(size: 10)).foregroundColor(ruler),
                                 at: CGPoint(x: x, y: 4), anchor: .top)
                    }
                    for r in minRow...maxRow {
                        let y = center.y + (CGFloat(r) - pan.y) * cell
                        ctx.draw(Text("\(r)").font(.system(size: 10)).foregroundColor(ruler),
                                 at: CGPoint(x: 4, y: y), anchor: .leading)
                    }

                    // 原点 (0,0) 红圈标记
                    let o = screenPoint(of: 0, 0, in: size, cell: cell)
                    ctx.stroke(Path(ellipseIn: CGRect(x: o.x - 4, y: o.y - 4, width: 8, height: 8)),
                               with: .color(.red.opacity(0.85)), lineWidth: 1.5)

                    // 悬停预览（AI 思考中 / 人机模式 AI 回合不显示）
                    if let h = hover, model.stones[Coord(h.0, h.1)] == nil, model.winner == nil,
                       !model.isDraw, !model.aiThinking,
                       !(model.mode == .ai && model.current == .white) {
                        let p = screenPoint(of: h.0, h.1, in: size, cell: cell)
                        let rad = cell * 0.42
                        let previewColor: Color = (model.current == .black ? Color.black : Color.white).opacity(0.35)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2)),
                                 with: .color(previewColor))
                    }

                    // 棋子（仅可见范围）
                    for (coord, p) in model.stones {
                        let pt = screenPoint(of: coord.row, coord.col, in: size, cell: cell)
                        guard pt.x > -cell, pt.x < size.width + cell,
                              pt.y > -cell, pt.y < size.height + cell else { continue }
                        let rad = cell * 0.42
                        let stone = Path(ellipseIn: CGRect(x: pt.x - rad, y: pt.y - rad, width: rad * 2, height: rad * 2))
                        let grad = Gradient(colors: p == .black
                                            ? [Color(white: 0.45), .black]
                                            : [.white, Color(white: 0.78)])
                        let centerG = CGPoint(x: pt.x - rad * 0.3, y: pt.y - rad * 0.3)
                        ctx.fill(stone, with: .radialGradient(grad, center: centerG, startRadius: 1, endRadius: rad))
                        if p == .white {
                            ctx.stroke(stone, with: .color(.gray.opacity(0.5)), lineWidth: 1)
                        }
                    }

                    // 最后落子红圈标记
                    if let last = model.moves.last, model.winner == nil, !model.isDraw {
                        let pt = screenPoint(of: last.row, last.col, in: size, cell: cell)
                        let rad = cell * 0.42
                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - rad, y: pt.y - rad, width: rad * 2, height: rad * 2)),
                                   with: .color(.red), lineWidth: 2)
                    }

                    // AI 提示标记（分屏模式仅本侧可见）：绿色虚线框 + 星标
                    if hintVisible, let h = model.aiHint {
                        let pt = screenPoint(of: h.row, h.col, in: size, cell: cell)
                        let rad = cell * 0.46
                        ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - rad, y: pt.y - rad, width: rad * 2, height: rad * 2)),
                                   with: .color(.green),
                                   style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                        ctx.draw(Text("★").font(.system(size: cell * 0.5)).foregroundColor(.green),
                                 at: pt, anchor: .center)
                    }

                    // 胜利连线高亮
                    if model.winner != nil, !model.winLine.isEmpty {
                        var path = Path()
                        for (i, coord) in model.winLine.enumerated() {
                            let pt = screenPoint(of: coord.row, coord.col, in: size, cell: cell)
                            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                        ctx.stroke(path, with: .color(.yellow),
                                   style: StrokeStyle(lineWidth: cell * 0.2, lineCap: .round, lineJoin: .round))
                    }
                }
                // 落子脉冲光环（动画层）
                if let last = model.moves.last, model.winner == nil, !model.isDraw {
                    let pt = screenPoint(of: last.row, last.col, in: geo.size, cell: cell)
                    Circle()
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: cell * 0.9, height: cell * 0.9)
                        .position(pt)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil { dragStart = value.location; panStart = pan }
                        let dx = value.location.x - dragStart!.x
                        let dy = value.location.y - dragStart!.y
                        if abs(dx) + abs(dy) > 4 { isDragging = true }
                        if isDragging, let ps = panStart {
                            pan = CGPoint(x: ps.x - dx / cell, y: ps.y - dy / cell)
                        }
                    }
                    .onEnded { value in
                        let dx = value.location.x - dragStart!.x
                        let dy = value.location.y - dragStart!.y
                        if abs(dx) + abs(dy) <= 4 {
                            let (r, c) = boardCoord(from: value.location, in: geo.size, cell: cell)
                            onPlace(r, c)
                        }
                        dragStart = nil; panStart = nil; isDragging = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if isDragging { hover = nil; return }
                    let (r, c) = boardCoord(from: p, in: geo.size, cell: cell)
                    hover = (model.stones[Coord(r, c)] == nil) ? (r, c) : nil
                case .ended:
                    hover = nil
                }
            }
            .onChange(of: model.moves.count) { old, new in
                if new > old {
                    ringScale = 1.7; ringOpacity = 0.9
                    withAnimation(.easeOut(duration: 0.45)) { ringScale = 1; ringOpacity = 0 }
                }
            }
        }
    }
}
