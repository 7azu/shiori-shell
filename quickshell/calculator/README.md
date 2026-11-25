# Calculator

Glass calculator in iOS style, built from the existing Theme/WalColors tokens.

- Open: app launcher → Calculator, or the calculator key (`XF86Calculator`). For a quick result without
  this window, type `=` and an expression into the app launcher search.
- IPC: `qs ipc call calculator open`, `toggle`, `close`.
- Enter computes, Backspace removes one digit, Delete clears, Escape closes.
- Ctrl+C copies the result. Comma and point both work as the decimal separator.
- Operator precedence, brackets, signs, percent (10% = 0.1).
- The history keeps the last 30 calculations until the shell restarts.
- Blur: `quickshell:calculator` in `hypr/modules/windows.lua`; full-screen dimming with alpha 0.4, the calculator card with alpha 0.72. A click next to the card closes it.

Logic: `services/CalculatorState.qml`, parser: `calculator/Engine.js`, UI: `windows/CalculatorWindow.qml`.
