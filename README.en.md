# Gomoku · Five-in-a-Row (macOS)

[中文版 / Chinese version](README.md)

A macOS Gomoku (Five-in-a-Row) game built with **Swift + SwiftUI**. Features AI opponents with five difficulty levels, two-player split-screen mode, and real-time AI hints. Infinite board with zoom and pan.

## Features

- **Game modes**: Switch between Player vs AI and two-player modes
- **Five difficulty levels**: Trivial → Beginner → Medium → Hard → Unbeatable, with a clear strength curve (Unbeatable is near unsolvable; Trivial loses on purpose)
- **Split-screen two-player**: Two board panels side by side; place a sheet of paper between them so players can't see each other's screen. Both boards stay perfectly synchronized
- **AI hints (Black only)**: A toggle that automatically shows the AI's recommended move (green dashed frame + ★) every turn and refreshes after the opponent moves. White never sees any hint
- **Move-record import / export**: Save and replay games
- **Resign / Draw**, live score, timer, undo
- **Infinite board**: Scroll to zoom, drag to pan, hover preview
- **Sound effects** on placing stones

## Requirements

- macOS 14.0 or later
- Swift 5.9+ (Swift 6 also works)

## Build & Run

**Option 1: Command line (recommended)**

```bash
git clone https://github.com/Wolfzzzzz/gomoku.git
cd gomoku
swift build -c release
./.build/release/Gomoku
```

**Option 2: Xcode**

Open `Package.swift` in Xcode and run the `Gomoku` scheme (⌘R).

**Option 3: Download**

Get the signed `Gomoku.app` from [Releases](../../releases) and double-click to run.

## How to use

| Action | Description |
|---|---|
| Switch mode | Toolbar: "Player vs AI" / "Two Players" |
| Set difficulty | In AI mode, pick from the difficulty menu |
| Split screen | In two-player mode, toggle "Split Screen"; place paper between |
| AI hint | In two-player mode, toggle "AI Hint" (serves Black only) |
| Undo | Toolbar "Undo" button |
| Place stone | Click an intersection; scroll to zoom, drag to pan on the infinite board |

## Project structure

```
gomoku/
├── Package.swift
├── Sources/Gomoku/
│   ├── GomokuApp.swift    # App entry point
│   ├── ContentView.swift  # Main UI and toolbar
│   ├── BoardView.swift    # Board rendering
│   ├── SidePanel.swift    # Side panel (score / timer / hint)
│   ├── GameModel.swift    # Game state machine + AI hint logic
│   └── AIPlayer.swift     # AI strength (five difficulty levels)
├── README.md              # Chinese docs
└── README.en.md           # English docs
```

## License

[MIT License](LICENSE) © 2026 Wolfzzzzz
