# Changelog

## 0.4.0 — 2026-11-18
- **Attention pulse:** new marks send out two fading rings so they're easy to spot on big or multiple screens
  (`pulse=false` to turn off).
- **⌃⌥⌘C clears everything**, from any app, without Accessibility permission. Clearing from the shortcut or the
  menu tells waiting agents: pending tasks report `dismissed`, guides report `cancelled`.
- **Start at login:** `annotate login on|off|status`, or the menu-bar toggle (a per-user LaunchAgent).
- `scripts/release.sh` for future releases. Tests: 55 checks.

## 0.3.0 — 2026-11-18
- **Window anchoring:** `window=Chrome` (app name, title, window id or `front`) makes coordinates relative to
  that window; marks follow it as it moves or changes display and hide while it's minimized or on another desktop.
- **Guided mode:** `guide` tool / `annotate guide` shows steps one at a time with a "✓ Next (n/N)" button and
  advances on its own; ✕ cancels. `wait_for_click` on the guide id returns `completed` or `cancelled`.
- `list_windows` tool / `annotate windows`.
- `annotate quit` now waits for the daemon to exit.
- Tests: 50 end-to-end checks, including a real moving window.

## 0.2.0 — 2026-11-18
- Clickable **✓ Done** and **✕** buttons on marks (the rest of the overlay stays click-through).
- `wait_for_click` MCP tool and `annotate wait` CLI, so an assistant can walk through steps one at a time.
- Claude Code plugin + marketplace manifest, bundled skill, Claude Desktop extension manifest.
- Universal binary (Apple Silicon + Intel), macOS 13+.
- `annotate tutorial` / `run_tutorial`: interactive first-run walkthrough.
- End-to-end test suite (`tests/run.sh`), technical spec (`docs/SPEC.md`), MIT license.

## 0.1.0 — 2026-11-18
- Transparent, click-through overlay on any display; all desktops or pinned to one.
- Shapes: circle, rect, highlight, arrow, label, numbered marker, spotlight; urgency color-coding.
- MCP server and CLI; display selection by index, name, or physical position.
