# Screen Annotator: technical specification

Version 0.2 · macOS 13+ · Swift, AppKit, no third-party dependencies.

## 1. Goals

- Let a program (usually an AI agent) visually point at things on a user's screens.
- Never get in the user's way: click-through, no focus stealing, no permissions for drawing.
- Be agent-agnostic: MCP for AI apps, a CLI for scripts, a JSON socket for anything else.
- Close the loop: let the user tell the agent "done" by clicking on screen.

Non-goals: capturing the screen, controlling mouse or keyboard, Windows/Linux support.

## 2. Architecture

```
 AI app ──MCP stdio──▶ annotate mcp ─┐
 script ──argv──────▶ annotate <cmd> ├─JSON lines─▶ /tmp/screen-annotator-<uid>.sock ─▶ annotate daemon
 any program ─────────────────────────┘                                                    │
                                                                    one overlay window per display
                                                                    + one button panel per mark
```

One binary, `annotate`, has three roles chosen by its first argument:

| Role | Process lifetime | Notes |
| --- | --- | --- |
| `daemon` | Long-lived background app | Owns all windows and state. Auto-spawned by clients |
| `mcp` | One per AI-app session | Stateless translator from MCP tool calls to socket requests |
| CLI commands | One per command | Thin socket client |

Clients start the daemon if the socket doesn't answer (`posix_spawn` with `POSIX_SPAWN_SETSID`, stdio to
`/dev/null`), then poll the socket for up to 3 s. Only one daemon runs per user; a second exits after a
successful ping.

### Source layout

| File | Responsibility |
| --- | --- |
| `main.swift` | CLI parsing and dispatch |
| `MCP.swift` | MCP server (JSON-RPC 2.0 over stdio) and tool catalogue |
| `Client.swift` | Socket client, daemon auto-spawn |
| `Daemon.swift` | Socket server, request handling, menu bar item, app lifecycle |
| `Overlay.swift` | Overlay windows, drawing, annotation store |
| `Controls.swift` | Clickable button panels, click events |
| `Model.swift` | Shape parsing and validation, units, colors |
| `Displays.swift` | Display discovery, arrangement labels, selector resolution |
| `Tutorial.swift` | Interactive first-run tutorial |

## 3. Windows

**Overlay window** (one per display, plus one per pinned mark):
borderless `NSWindow`, clear background, `ignoresMouseEvents = true`, level `.screenSaver`,
collection behavior `canJoinAllSpaces | stationary | fullScreenAuxiliary | ignoresCycle`
(pinned marks omit `canJoinAllSpaces` and `stationary`, so they stay on the Space where they were shown).
The content view is flipped, so drawing uses the same top-left origin as screenshots. Windows are ordered
out when their display has no marks.

**Button panel** (one per mark with `task` or `dismissible`; one per `id`+display group):
borderless, non-activating `NSPanel` at level `.screenSaver + 1`, `canBecomeKey = false`,
`acceptsFirstMouse = true`. It receives clicks without activating the daemon or changing the key window.

The daemon runs with activation policy `.accessory`: no Dock icon, never frontmost.
It listens for `didChangeScreenParametersNotification` and re-fits windows when displays change.

## 4. Coordinates

- Origin: top-left of the target display. x right, y down.
- `points` (default): AppKit points, i.e. the "looks like" resolution.
- `pixels`: divided by the display's `backingScaleFactor`.
- `fraction`: x × width, y × height; radius × min(width, height).
- `display=all` repeats the shape on every display using that display's own size.

Display selectors resolve in this order: number → index; `main`/`primary`; `all`; `id:<CGDirectDisplayID>`;
`mouse`; `left`/`right`/`top`/`bottom` (extreme midX/midY of display frames); `builtin`; exact position label
(`upper-left` …); case-insensitive name substring (must be unique).

Position labels compare each display's center with the center of the union of all displays, with a 10 %
tolerance band that yields `center`/no vertical component.

## 5. Socket protocol

Unix domain stream socket at `/tmp/screen-annotator-<uid>.sock`, mode `0600`. Each request is one JSON
object on one line; each gets one JSON object line back. Responses always include `"ok": true|false`, and
`"error"` when false. A connection may carry many requests.

| `cmd` | Request fields | Response |
| --- | --- | --- |
| `ping` | — | `version`, `annotations` (count) |
| `list_displays` | — | `displays[]`: `index id name position is_main has_mouse width height scale pixel_width pixel_height global_x global_y` |
| `draw` | `shapes[]` and/or `shape{}`, plus any shape option as a default for all shapes, `clear_first` | `drawn[]` (summaries) |
| `clear` | optional `id`, `display` | `cleared`, `remaining` |
| `list` | — | `annotations[]` |
| `events` | optional `id`, `consume` (default true) | `event` (oldest unread click, or null) |
| `quit` | — | daemon exits after replying |
| `_simulate_click` | `id`, `action` | test hook; behaves like a user click |

`draw` is atomic: every shape is validated before any is shown.

Annotation summary: `id type display pinned_to_space` plus `bounds [x,y,w,h]` (or `from`/`to` for arrows,
`at` for labels), `text`, `label`, `task`, `expires_in_seconds`.

Click event: `id action("done"|"dismissed") display label at(ISO 8601) seconds_ago`. The store keeps the
last 500 events. Each is returned once when consumed.

## 6. Shape model

Required fields per type are listed in the README. Validation errors name the missing field.
Type aliases: `ellipse`→circle, `box`/`rectangle`→rect, `text`→label, `badge`/`number`→marker.
`id` defaults to `a1`, `a2`, …. Shapes sharing an `id` on one display are cleared, completed and given buttons
as a group.

Rendering order: spotlights first, then everything else in insertion order. Strokes get a soft black shadow
so they read on light and dark content. Label pills choose black or white text by the fill's luminance.
Captions sit above the shape (below when there's no room, inside as a last resort) and are clamped to the
display. Arrow captions sit beyond the tail.

On **✓ Done**: record event, recolor the group green with caption "✓ <done_text>", remove after 0.9 s.
On **✕**: record event, remove immediately.

## 7. MCP server

JSON-RPC 2.0, newline-delimited, over stdio. Implements `initialize` (echoes the client's
`protocolVersion`, advertises `tools`, provides usage `instructions`), `ping`, `tools/list`, `tools/call`.
Notifications are ignored. Unknown methods return `-32601`. Tool failures return `isError: true` with a
readable message rather than a protocol error.

Tools map to socket commands (`draw_*` → `draw` with one shape; `annotate` → `draw`; `clear`;
`list_annotations` → `list`; `list_displays`). `wait_for_click` polls `events` every 300 ms up to
`timeout_seconds` (default 120, max 600). `run_tutorial` runs the tutorial and returns its transcript.

## 8. Security and privacy

- The socket is only reachable by the same macOS user (file mode 0600 under `/tmp`).
- Nothing listens on the network. Nothing reads screen contents. No telemetry.
- The overlay can't receive input except through the explicit ✓/✕ panels.
- Any process running as the user can draw. That is the same trust level as the user's own shell.

## 9. Testing

`tests/run.sh` is an end-to-end suite (37 checks) that drives the real binary: CLI, every shape, units,
display selectors, validation errors, atomic batches, click events via `_simulate_click`, and the MCP
protocol. It needs a logged-in session with at least one display and draws briefly. CI runs it on a
GitHub-hosted macOS runner after a universal build.

## 10. Packaging

- `scripts/build-release.sh`: universal (`arm64` + `x86_64`) build → `bin/annotate` (bundled in the Claude
  Code plugin), `dist/annotate-<ver>-macos.tar.gz`, `dist/mcpb/` (staged Claude Desktop extension;
  pack with `npx @anthropic-ai/mcpb pack dist/mcpb`).
- Claude Code plugin: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.mcp.json`
  (runs `scripts/annotate-launcher.sh`, which uses the bundled binary or builds from source),
  `skills/screen-annotations/SKILL.md`.
- Binaries are not yet signed or notarized.

## 11. Roadmap

- Window targeting: anchor marks to an app window by name and follow it as it moves.
- Guided mode: queue steps that appear one by one as the user presses Done.
- Attention pulse on new marks, global clear shortcut, launch at login.
- Signed and notarized builds; Homebrew tap.
