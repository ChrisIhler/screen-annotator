# Changelog

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
