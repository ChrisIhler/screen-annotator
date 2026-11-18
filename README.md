# Screen Annotator

**On-screen pointing for AI agents on macOS.** Let Claude, or any AI tool that speaks
[MCP](https://modelcontextprotocol.io), or any script, draw on top of your screens: circle a button,
point an arrow at a field, box a region, highlight a line, drop numbered step markers, or spotlight
one area. Each step can carry a clickable **✓ Done** button, so the AI can walk you through a task one
step at a time and continue when you press it.

The drawings live in a transparent, **click-through**, always-on-top overlay. You keep working underneath;
clicks and typing pass straight through to your apps. Drawing needs **no macOS permissions**.

## Works with any AI (or none)

Screen Annotator isn't tied to one assistant. It offers three interfaces to the same overlay:

| Interface | Who uses it |
| --- | --- |
| **MCP server** (`annotate mcp`) | Claude Code, Claude Desktop, and any other MCP-capable app or agent framework |
| **Command line** (`annotate circle …`) | Shell scripts, other AI tools that can run commands, you |
| **JSON over a local socket** | Any program in any language (see [docs/SPEC.md](docs/SPEC.md)) |

## Install

### Claude Code plugin (easiest for Claude users)

```
/plugin install screen-annotator --marketplace ChrisIhler/screen-annotator
```

Includes a prebuilt universal binary, the MCP server, and a skill that teaches Claude how to point at things.

### Download the binary (any MCP client)

1. Download `annotate-<version>-macos.tar.gz` from [Releases](https://github.com/ChrisIhler/screen-annotator/releases) and unpack it.
2. Move `annotate` somewhere permanent, for example `~/.local/bin/annotate`.
3. If macOS blocks it the first time ("unidentified developer"), run `xattr -d com.apple.quarantine ~/.local/bin/annotate`.
4. Point your AI app's MCP settings at it:

```json
{
  "mcpServers": {
    "screen-annotator": { "command": "/Users/YOU/.local/bin/annotate", "args": ["mcp"] }
  }
}
```

For Claude Desktop this file is `~/Library/Application Support/Claude/claude_desktop_config.json`.
For Claude Code: `claude mcp add --scope user screen-annotator -- ~/.local/bin/annotate mcp`.
Other MCP clients (Cursor, VS Code, agent frameworks) use the same command and argument.

### Build from source

```bash
git clone https://github.com/ChrisIhler/screen-annotator.git
cd screen-annotator
./scripts/install.sh          # builds and installs ~/.local/bin/annotate
```

Needs Apple's Command Line Tools (`xcode-select --install`). Full Xcode isn't required. macOS 13+, Apple Silicon or Intel.

## First run: the 1-minute tutorial

```bash
annotate tutorial
```

On the screen under your mouse pointer it shows each kind of mark, asks you to press **✓ Next**,
shows that clicks pass through the marks, has you close one with **✕**, and checks whether screenshots
can see your screen. AI apps can start the same tutorial with the `run_tutorial` tool, so you can just ask
your assistant to "show me how screen annotations work".

## macOS permissions

- **Drawing: none.** The overlay is an ordinary window that ignores the mouse.
- **Screen Recording:** only for whatever *takes screenshots* so the AI can see where to draw (for example
  Claude's computer-use tool). Screen Annotator itself never reads your screen.
- **Accessibility:** not used. It does not control your mouse or keyboard.

## Displays and coordinates

```bash
annotate displays
```

Each display gets an `index`, its `name`, a `position` from your arrangement in System Settings › Displays
(`upper-left`, `lower-right`, …), its size in points, and whether the mouse is on it.

| `display=` | Meaning |
| --- | --- |
| `0`, `1`, `2` | Index from `annotate displays` |
| `HDR`, `ultrawide`, `built-in` | Any part of the display name, or the built-in laptop screen |
| `left`, `right`, `top`, `bottom` | Physical arrangement |
| `main` | The display with the menu bar (default) |
| `mouse` | The display under the pointer |
| `all` | Every display |

Coordinates start at the **top-left of the chosen display**. `units=`:
`points` (default, macOS points), `pixels` (physical pixels, e.g. from a Retina screenshot), or
`fraction` (0–1 of width/height, best when the AI is looking at a scaled screenshot).

## Shapes

| Shape | Fields | Notes |
| --- | --- | --- |
| `circle` | `x y radius` | x,y is the center |
| `circle` | `x y width height` | Ellipse *around* that box, with padding |
| `rect` | `x y width height` | Outline; optional `corner_radius`, `fill_opacity` |
| `highlight` | `x y width height` | Translucent highlighter, yellow by default |
| `arrow` | `from_x from_y to_x to_y` | Head at `to`; a `label` sits at the tail |
| `label` | `x y text` | Text pill; x,y is its top-left. Emoji welcome |
| `marker` | `x y number` | Numbered badge centered at x,y |
| `spotlight` | `x y width height` | Dims the rest of the display; `dim` sets darkness |

| Option (any shape) | Meaning |
| --- | --- |
| `label` | Text pill attached to the shape |
| `urgency` | `urgent` = 🔴 red, `soon` = 🟡 yellow, `fyi` = 🔵 blue; also prefixes the label |
| `color` | `red`, `orange`, `green`, `blue`, `purple`… or `#RRGGBB` / `#RRGGBBAA` |
| `line_width`, `font_size`, `opacity` | Styling |
| `window` | Anchor to an app window (see above); the mark follows it |
| `id` | Name it, to clear it or wait for its click |
| `task` / `done_text` | Add a clickable **✓ Done** button (custom text with `done_text`) |
| `dismissible` | Show the clickable **✕** (default `true`) |
| `duration_seconds` | Clear automatically |
| `pulse` | Two attention rings when the mark appears (default `true`) |
| `pin_to_current_space` | Show only on the current desktop (default: all desktops) |
| `clear_first` | Wipe the target display before drawing |

## Point at a window, not just a screen

Add `window=` to any shape to anchor it to an app window: an app name (`Chrome`, `Outlook`), part of a window
title, a `window_id` from `annotate windows`, or `front` for the active app. Coordinates become relative to the
window's top-left (`units=fraction` means a fraction of the window), and the mark **follows the window** when you
move it, even to another monitor. It hides while the window is minimized or on another desktop and comes back with it.

```bash
annotate windows
annotate circle window=Chrome units=fraction x=0.9 y=0.05 radius=20 urgency=urgent label="Extensions"
```

App names and positions need no permission; window titles are only visible with Screen Recording permission.

## Guided mode

Give a list of steps and Screen Annotator runs the walkthrough by itself: step 1 appears with
**✓ Next (2/3)**, pressing it shows step 2, and the last step says **✓ Done**. **✕** cancels.

```bash
annotate guide '{"id":"save","window":"Pages","units":"fraction","steps":[
  {"title":"Open the File menu","shapes":[{"type":"circle","x":0.05,"y":0.02,"radius":0.02}]},
  {"title":"Choose Export To › PDF","shapes":[{"type":"arrow","from_x":0.3,"from_y":0.3,"to_x":0.12,"to_y":0.2}]},
  {"title":"Click Next, then Save","shapes":[{"type":"highlight","x":0.6,"y":0.8,"width":0.3,"height":0.06}]}
]}'
annotate wait id=save        # → "completed" or "cancelled"
```

An agent calls the `guide` tool once and `wait_for_click` with the guide id, instead of drawing and waiting
step by step.

## Clickable buttons

The overlay is click-through except for a small button strip beside each mark's label:
**✕** removes the mark; **✓ Done** flashes it green, then removes it. The buttons never take focus from the
app you're in. Every click is recorded once and can be read with `wait_for_click` (MCP) or `annotate wait` (CLI).

## Command line

```bash
annotate circle display=HDR x=600 y=400 radius=80 urgency=urgent label="Action 1"
annotate arrow display=left units=fraction from_x=0.2 from_y=0.2 to_x=0.5 to_y=0.5 urgency=soon label="Action 2"
annotate marker display=right x=900 y=300 number=1 label="Click Save" done_text="Task complete" id=step1
annotate wait id=step1 timeout=300     # prints {"action":"done",...} when pressed
annotate windows
annotate guide '[{"type":"marker","x":100,"y":100,"number":1,"label":"First"},{"type":"marker","x":300,"y":100,"number":2,"label":"Then"}]'
annotate list
annotate clear                         # or: clear display=HDR / clear id=step1
annotate tutorial
annotate quit                          # stop the overlay
```

Run `annotate help` for everything.

## MCP tools

| Tool | What it does |
| --- | --- |
| `list_displays` | Display names, arrangement, sizes, scale, mouse location |
| `draw_circle`, `draw_rect`, `highlight`, `draw_arrow`, `label`, `marker`, `spotlight` | Draw one shape |
| `annotate` | Draw several shapes in one call |
| `guide` | Step-by-step walkthrough that advances on ✓ Next |
| `list_windows` | Visible app windows (app, id, bounds, display, title) |
| `wait_for_click` | Wait for (or, with `timeout_seconds: 0`, check) a ✓ Done or ✕ click |
| `clear` | Clear all, or by `id` / `display` |
| `list_annotations` | What is on screen now |
| `run_tutorial` | Interactive first-run walkthrough |

Typical agent flow: screenshot → `list_displays` / `list_windows` → `guide` with all steps (anchored with
`window` and `units: "fraction"`) → `wait_for_click` on the guide id → `clear`.

## Desktops (Spaces)

Marks follow you to every desktop by default. With `pin_to_current_space=true` a mark stays on the desktop
that was active when it was drawn. macOS offers no public way to target a desktop by number, so switch to it
first.

## Menu bar, shortcut and login

While the overlay runs, a pencil icon in the menu bar shows the mark count, **Clear all**, **Start at login**
and **Quit**. Press **⌃⌥⌘C** (Control-Option-Command-C) in any app to clear every mark; no permission needed.
Clearing this way tells a waiting AI that its steps were dismissed or cancelled.

```bash
annotate login on      # start the overlay automatically when you log in (off: annotate login off)
```

New marks pulse twice so they're easy to find. Pass `pulse=false` for a quiet mark.

## Development

```bash
swift build                 # debug build
tests/run.sh                # end-to-end tests (draws briefly on your screen)
./scripts/build-release.sh  # universal binary, plugin binary, release tarball
```

See [docs/SPEC.md](docs/SPEC.md) for the architecture and protocol, [CONTRIBUTING.md](CONTRIBUTING.md),
and [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © 2026 Chris Ihler. Not affiliated with Anthropic.
