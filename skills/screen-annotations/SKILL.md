---
name: screen-annotations
description: Point at things on the user's Mac screens with the screen-annotator MCP tools (circles, arrows, numbered steps, Done buttons). Use when guiding the user through steps in an app, showing where something is on screen, or when they ask "where is it?" or "show me".
---

# Pointing at things on screen

1. Look first. Take a screenshot if you have a screenshot tool, then call `list_displays` to learn each
   display's name, position (upper-left, lower-right...) and size.
2. Draw with `units: "fraction"` (0–1 of the display) when working from a scaled screenshot, so scaling never
   throws off your aim. Target the display by name fragment (`"HDR"`, `"built-in"`) or position (`"left"`).
3. Color-code with `urgency`: `urgent` 🔴 for the action to take now, `soon` 🟡 for next, `fyi` 🔵 for context.
   Give each action a short `label` such as "Action 1: click Save".
4. In chat, name the monitor, the desktop and the window, and number the actions to match the marks.
5. For step-by-step help, draw one step with `task: true` (or `done_text: "Task complete"`) and a stable `id`,
   call `wait_for_click` with that id, and draw the next step when it returns `"action": "done"`.
   `"dismissed"` means the user closed it with ✕; ask before continuing.
6. Clean up: `clear` when you're finished pointing, or set `duration_seconds` for passing hints.

Drawing needs no macOS permissions. Screenshots need Screen Recording permission for the app taking them.
