# Gomoku · 五子棋（macOS）

[English version / 英文版](README.en.md)

一款用 **Swift + SwiftUI** 编写的 macOS 五子棋。支持人机对战（五档难度）、双人分屏对战、AI 实时提示等特性。无限棋盘，支持缩放与平移。

## 功能特性

- **对战模式**：人机对战 / 双人对战，一键切换
- **五档难度**：超简单 → 初级 → 中等 → 困难 → 超级难，强度阶梯清晰（超级难基本无解，超简单闭眼能赢）
- **双人分屏**：左右两块棋盘并排，中间放一张纸即可互看不见对方屏幕；两块棋盘数据实时同步
- **AI 提示（仅黑棋）**：开关式，开启后每回合自动显示 AI 推荐落点（绿色虚线框 + ★），对面落完自动刷新；白棋方永远看不到任何提示
- **棋谱导入 / 导出**：保存与复盘对局
- **认输 / 和棋**、实时比分、计时、悔棋
- **无限棋盘**：滚轮缩放、拖拽平移、悬停预览落子
- **音效**：落子音效

## 环境要求

- macOS 14.0 或更高
- Swift 5.9+（Swift 6 亦可）

## 构建与运行

**方式一：命令行（推荐）**

```bash
git clone https://github.com/Wolfzzzzz/gomoku.git
cd gomoku
swift build -c release
./.build/release/Gomoku
```

**方式二：Xcode**

用 Xcode 打开 `Package.swift`，选择 `Gomoku` scheme 运行（⌘R）。

**方式三：直接下载**

前往 [Releases](../../releases) 下载已签名的 `Gomoku.app`，双击即可运行。

## 使用说明

| 操作 | 说明 |
|---|---|
| 切换模式 | 顶部工具栏切换「人机对战 / 双人对战」 |
| 调整难度 | 人机模式下从难度菜单选择 |
| 双人分屏 | 双人对战下打开「分屏」开关，中间放纸隔开 |
| AI 提示 | 双人对战下打开「AI 提示」开关（仅服务黑棋方） |
| 悔棋 | 工具栏「悔棋」按钮 |
| 落子 | 点击棋盘交叉点；无限棋盘可滚轮缩放、拖拽平移 |

## 项目结构

```
gomoku/
├── Package.swift
├── Sources/Gomoku/
│   ├── GomokuApp.swift    # 应用入口
│   ├── ContentView.swift  # 主界面与工具栏
│   ├── BoardView.swift    # 棋盘渲染
│   ├── SidePanel.swift    # 侧边栏（比分 / 计时 / 提示）
│   ├── GameModel.swift    # 游戏状态机 + AI 提示逻辑
│   └── AIPlayer.swift     # AI 棋力（五档难度）
├── README.md              # 中文说明
└── README.en.md           # 英文说明
```

## 许可

[MIT License](LICENSE) © 2026 Wolfzzzzz
