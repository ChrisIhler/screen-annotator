# Screen Annotator

Let an AI assistant (or you) draw on top of your Mac's screens: circle a button, point an arrow at a field,
box a region, highlight a line, drop numbered step markers, or spotlight one area, then clear it all.

The drawings live in a transparent, **click-through**, always-on-top overlay. You can keep working underneath them;
clicks and typing pass straight through to your apps.

It ships as one small native binary, `annotate`, that works three ways:

| Mode | Use it for |
| --- | --- |
| `annotate mcp` | An [MCP](https://modelcontextprotocol.io) server, so Claude (or any MCP client) can draw with tools like `draw_circle`, `draw_arrow`, `clear` |
| `annotate circle …` | A command-line tool for scripts and quick use |
| `annotate daemon` | The overlay itself. It starts on its own the first time anything draws |

Requires macOS 13 or later. No third-party dependencies.

## Install

```bash
git clone <this repo> screen-annotator && cd screen-annotator
./scripts/install.sh          # builds and installs ~/.local/bin/annotate
```

Building needs Apple's Command Line Tools (`xcode-select --install`); full Xcode is not required.

### Connect it to Claude Code

```bash
claude mcp add --scope user screen-annotator -- ~/.local/bin/annotate mcp
```

### Connect it to Claude Desktop (or another MCP client)

Add this to `~/Library/Application Support/Claude/claude_desktop_config.json`, then restart the app:

```json
{
  "mcpServers": {
    "screen-annotator": { "command": "/Users/YOU/.local/bin/annotate", "args": ["mcp"] }
  }
}
```

## macOS permissions

**Drawing needs no permissions.** The overlay is an ordinary window that ignores the mouse, so macOS does not ask
for anything when it appears.

You may see these prompts only if you combine it with other tools:

- **Screen Recording.** Needed by whatever *takes screenshots* (for example Claude's computer-use tool, or
  `screencapture`) so the assistant can see where to draw. Screen Annotator itself never reads your screen.
- **Accessibility.** Not used. Screen Annotator does not control the mouse or keyboard and cannot switch
  desktops for you.

## Displays and coordinates

```bash
annotate displays
```

Each display gets an `index`, its `name`, a `position` worked out from your arrangement in
System Settings › Displays (`upper-left`, `lower-right`, …), its size in points, and whether the mouse is on it.

Choose a display with `display=`:

| Selector | Meaning |
| --- | --- |
| `0`, `1`, `2` | Index from `annotate displays` |
| `HDR`, `ultrawide`, `built-in` | Any part of the display name, or the built-in laptop screen |
| `left`, `right`, `top`, `bottom` | Physical arrangement |
| `main` | The display with the menu bar (the default) |
| `mouse` | Whichever display the pointer is on |
| `all` | Every display (same coordinates on each) |

Coordinates start at the **top-left of the chosen display**. Pick units with `units=`:

- `points` (default): macOS points, the "looks like" resolution in System Settings.
- `pixels`: physical pixels, handy when you measured on a full-resolution Retina screenshot (divides by the scale).
- `fraction`: 0 to 1 across the display's width and height. Best when working from a scaled-down screenshot.

## Shapes

| Shape | Fields | Notes |
| --- | --- | --- |
| `circle` | `x y radius` | x,y is the center |
| `circle` | `x y width height` | Draws an ellipse *around* that box, with padding |
| `rect` | `x y width height` | Outline; optional `corner_radius`, `fill_opacity` |
| `highlight` | `x y width height` | Translucent highlighter, yellow by default |
| `arrow` | `from_x from_y to_x to_y` | Head at `to`; a `label` sits at the tail |
| `label` | `x y text` | Text pill; x,y is its top-left. Emoji welcome |
| `marker` | `x y number` | Numbered badge centered at x,y |
| `spotlight` | `x y width height` | Dims the rest of the display; `dim` sets darkness |

Options for every shape:

| Option | Meaning |
| --- | --- |
| `label` | Text pill attached to the shape |
| `urgency` | `urgent` = 🔴 red, `soon` = 🟡 yellow, `fyi` = 🔵 blue; also prefixes the label with that emoji |
| `color` | Name (`red`, `orange`, `green`, `blue`, `purple`…) or `#RRGGBB` / `#RRGGBBAA` |
| `line_width`, `font_size`, `opacity` | Styling |
| `id` | Name it so you can clear just this one later |
| `duration_seconds` | Clear automatically after this long |
| `pin_to_current_space` | Show only on the desktop (Space) that is active now. Default: visible on all desktops |
| `clear_first` | Wipe the target display before drawing |

## CLI examples

```bash
annotate circle display=HDR x=600 y=400 radius=80 urgency=urgent label="Action 1"
annotate arrow  display=left units=fraction from_x=0.2 from_y=0.2 to_x=0.5 to_y=0.5 urgency=soon label="Action 2"
annotate highlight display=built-in x=100 y=200 width=500 height=40
annotate marker display=right x=900 y=300 number=3
annotate list
annotate clear                     # everything
annotate clear display=HDR         # one display
annotate clear id=step1            # one annotation
annotate demo display=mouse        # sample drawing that clears itself after 10 s
annotate quit                      # stop the overlay
```

## MCP tools

| Tool | What it does |
| --- | --- |
| `list_displays` | Display names, arrangement, sizes, scale, mouse location |
| `draw_circle`, `draw_rect`, `highlight`, `draw_arrow`, `label`, `marker`, `spotlight` | Draw one shape |
| `annotate` | Draw several shapes in one call (shared options at the top level) |
| `clear` | Clear all, or by `id` / `display` |
| `list_annotations` | What is on screen now |

A typical flow for an assistant: take a screenshot, call `list_displays`, draw with `units: "fraction"`
(so screenshot scaling doesn't matter), explain the numbered steps in chat, then `clear`.

## Desktops (Spaces)

By default annotations follow you to every desktop, so they stay put when you switch.
With `pin_to_current_space=true` an annotation stays on the desktop that was active when it was drawn.
macOS gives apps no public way to target a desktop by number, so to annotate Desktop 3 specifically,
switch to it first and then draw with `pin_to_current_space`.

## Menu bar

While anything is running, a small pencil icon sits in the menu bar showing the annotation count,
with **Clear all annotations** and **Quit Screen Annotator**.

## How it works

- `annotate daemon` is a background AppKit app (no Dock icon, never takes focus). It keeps one borderless,
  transparent window per display at screen-saver level, with `ignoresMouseEvents` so input passes through,
  and joins all Spaces and full-screen apps.
- It listens on a Unix socket at `/tmp/screen-annotator-<uid>.sock` (mode 0600, only your user can connect)
  and speaks newline-delimited JSON: `{"cmd":"draw","shapes":[…]}`, `clear`, `list`, `list_displays`, `ping`, `quit`.
- `annotate mcp` and the CLI are thin clients. They start the daemon if it isn't running.
- Display changes (plugging in a monitor, rearranging) are picked up automatically.

```
Sources/annotate/
  main.swift      CLI entry point
  MCP.swift       MCP server and tool catalogue
  Client.swift    socket client, daemon auto-start
  Daemon.swift    socket server, command handling, menu bar item
  Overlay.swift   overlay windows and drawing
  Model.swift     shape parsing, units, colors
  Displays.swift  display discovery and selectors
```

## Ideas for later

- Pulse or fade-in animation to draw the eye
- Freehand paths and curved arrows
- A signed `.app` bundle with login-item support, and a Claude plugin/connector package

## License

Not chosen yet. Until a license file is added, all rights are reserved by the author.
