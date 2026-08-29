import SwiftUI

struct SidePanel: View {
    @ObservedObject var model: GameModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(model.current == .black ? Color.black : Color.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.gray))
                if model.mode == .ai && model.aiThinking {
                    Text("AI 思考中…").font(.headline)
                } else {
                    Text("轮到：\(model.current.label)").font(.headline)
                }
            }

            if model.mode == .ai {
                Label(model.aiThinking ? "AI（白方）正在落子" : "你执黑 · AI 执白", systemImage: "cpu")
                    .font(.caption).foregroundColor(.secondary)
            }

            if let w = model.winner {
                Label("\(w.label) 获胜！", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green).font(.headline)
            } else if model.isDraw {
                Label("和棋", systemImage: "equal.circle.fill")
                    .foregroundColor(.orange).font(.headline)
            }

            Divider()

            // 累计比分
            HStack {
                Text("比分").font(.subheadline.bold())
                Spacer()
                Text("黑 \(model.blackWins) : \(model.whiteWins) 白")
                    .monospacedDigit().font(.subheadline.bold())
            }

            HStack { Text("黑方用时"); Spacer(); Text(model.format(model.blackTime)).monospacedDigit() }
            HStack { Text("白方用时"); Spacer(); Text(model.format(model.whiteTime)).monospacedDigit() }

            Divider()

            Text("棋谱（\(model.moves.count) 步）").font(.subheadline.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.moves.enumerated()), id: \.element.id) { i, m in
                        Button { model.undoTo(index: i + 1) } label: {
                            HStack {
                                Text("\(i + 1).").foregroundColor(.gray)
                                Text(m.player.label).foregroundColor(m.player == .black ? .primary : .secondary)
                                Spacer()
                                Text(m.coord()).monospacedDigit().foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(width: 220)
        .background(.ultraThinMaterial)
    }
}
