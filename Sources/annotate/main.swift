import Foundation

let usage = """
annotate \(annotatorVersion) — draw annotations over your Mac's screens

USAGE
  annotate mcp                       Run as an MCP server on stdio (for Claude)
  annotate daemon                    Run the overlay (normally auto-started)
  annotate displays                  List displays and their arrangement
  annotate <shape> key=value ...     Draw a shape (see below)
  annotate clear [display=..] [id=..]  Clear annotations (all by default)
  annotate list                      List annotations on screen
  annotate windows                   List app windows (for window=…)
  annotate guide '<json>'            Step-by-step guide that advances on ✓ Next
  annotate wait [id=..] [timeout=120]  Wait for a click on a ✓ Done / ✕ button
  annotate tutorial                  Interactive 1-minute walkthrough (start here)
  annotate demo [display=right]      Draw a sample set for 10 seconds
  annotate json '<request>'          Send a raw JSON request to the daemon
  annotate quit                      Stop the overlay daemon

SHAPES
  circle     x y radius            (center)  — or x y width height (box to circle)
  rect       x y width height
  highlight  x y width height
  arrow      from_x from_y to_x to_y
  label      x y text
  marker     x y number
  spotlight  x y width height

COMMON OPTIONS
  display=0|HDR|ultrawide|built-in|left|right|top|bottom|main|mouse|all
  window=Chrome|front|<window_id>   (coordinates relative to that window; follows it)
  units=points|pixels|fraction   color=red|#FF8800   urgency=urgent|soon|fyi
  label="Action 1"   id=name   line_width=5   duration_seconds=10
  pin_to_current_space=true   clear_first=true
  task=true (adds a clickable "✓ Done" button)   done_text="Task complete"
  dismissible=false (hide the clickable ✕)

EXAMPLES
  annotate circle display=HDR x=600 y=400 radius=80 urgency=urgent label="Action 1"
  annotate arrow display=left from_x=0.2 from_y=0.2 to_x=0.5 to_y=0.5 units=fraction
  annotate clear
"""

func printJSON(_ obj: Any) {
    if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let s = String(data: d, encoding: .utf8) { print(s) }
}

func parseKV(_ args: ArraySlice<String>) -> [String: Any] {
    var d: [String: Any] = [:]
    for a in args {
        guard let eq = a.firstIndex(of: "=") else { continue }
        let k = String(a[..<eq]).replacingOccurrences(of: "-", with: "_")
        let v = String(a[a.index(after: eq)...])
        if let n = Double(v) { d[k] = n }
        else if v == "true" || v == "false" { d[k] = (v == "true") }
        else { d[k] = v }
    }
    return d
}

func send(_ req: [String: Any]) -> Never {
    do {
        let resp = try Client.request(req)
        printJSON(resp)
        exit((resp["ok"] as? Bool ?? false) ? 0 : 1)
    } catch {
        FileHandle.standardError.write(Data("annotate: \(error)\n".utf8))
        exit(1)
    }
}

let argv = CommandLine.arguments
let cmd = argv.count > 1 ? argv[1].lowercased() : "help"
let rest = argv.dropFirst(2)

switch cmd {
case "daemon", "serve":
    runDaemon()
case "mcp":
    MCPServer.run()
case "displays", "list_displays":
    send(["cmd": "list_displays"])
case "list":
    send(["cmd": "list"])
case "windows", "list_windows":
    send(["cmd": "list_windows"])
case "guide":
    // annotate guide '<json steps array or {"steps":[...], ...}>'
    guard let raw = rest.first, let d = raw.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) else {
        print("usage: annotate guide '{\"steps\":[{\"title\":\"…\",\"shapes\":[…]}]}'"); exit(2)
    }
    var req: [String: Any] = (obj as? [String: Any]) ?? ["steps": obj]
    req.merge(parseKV(rest.dropFirst())) { a, _ in a }
    req["cmd"] = "guide"
    send(req)
case "clear":
    var r = parseKV(rest); r["cmd"] = "clear"; send(r)
case "quit", "stop":
    do { printJSON(try Client.request(["cmd": "quit"], autostart: false)) }
    catch { print("annotate: daemon is not running."); exit(0) }
    // Wait until it has really gone, so a following command starts a fresh one.
    for _ in 0..<40 where (try? Client.request(["cmd": "ping"], autostart: false)) != nil { usleep(50_000) }
    exit(0)
case "ping", "status":
    do { printJSON(try Client.request(["cmd": "ping"], autostart: false)) }
    catch { print("annotate: daemon is not running."); exit(1) }
    exit(0)
case "wait":
    // Poll for the next button click (CLI equivalent of wait_for_click).
    let o = parseKV(rest)
    let timeout = ShapeParser.num(o, "timeout") ?? ShapeParser.num(o, "timeout_seconds") ?? 120
    var req: [String: Any] = ["cmd": "events"]
    if let id = ShapeParser.str(o, "id") { req["id"] = id }
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if let r = try? Client.request(req), let e = r["event"] as? [String: Any] { printJSON(e); exit(0) }
        if Date() >= deadline { print("{\"clicked\": null}"); exit(1) }
        usleep(300_000)
    }
case "tutorial", "welcome", "setup":
    let o = parseKV(rest)
    let r = Tutorial.run(display: ShapeParser.str(o, "display") ?? "mouse") { print($0) }
    exit(r.completed ? 0 : 1)
case "json":
    guard let raw = rest.first, let d = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
        print("annotate json expects one JSON object argument."); exit(2)
    }
    send(obj)
case "demo":
    var opts = parseKV(rest)
    if opts["display"] == nil { opts["display"] = "mouse" }
    send([
        "cmd": "draw", "display": opts["display"]!, "units": "fraction",
        "duration_seconds": opts["duration_seconds"] ?? 10, "clear_first": true,
        "shapes": [
            ["type": "spotlight", "x": 0.55, "y": 0.55, "width": 0.3, "height": 0.25, "dim": 0.35, "color": "white"],
            ["type": "circle", "x": 0.25, "y": 0.3, "radius": 0.08, "urgency": "urgent", "label": "Action 1"],
            ["type": "arrow", "from_x": 0.4, "from_y": 0.25, "to_x": 0.53, "to_y": 0.5, "urgency": "soon", "label": "Action 2"],
            ["type": "rect", "x": 0.08, "y": 0.6, "width": 0.25, "height": 0.2, "urgency": "fyi", "label": "FYI: this area"],
            ["type": "highlight", "x": 0.6, "y": 0.1, "width": 0.3, "height": 0.06],
            ["type": "marker", "x": 0.7, "y": 0.68, "number": 3, "urgency": "urgent"],
            ["type": "label", "x": 0.6, "y": 0.2, "text": "Screen Annotator demo — clears in 10 s", "color": "black"],
        ],
    ])
case "help", "-h", "--help":
    print(usage)
case "version", "--version", "-v":
    print(annotatorVersion)
default:
    let kinds = Set(ShapeKind.allCases.map(\.rawValue) + ["ellipse", "box", "rectangle", "text", "badge"])
    guard kinds.contains(cmd) else {
        FileHandle.standardError.write(Data("annotate: unknown command '\(cmd)'\n\n\(usage)\n".utf8))
        exit(2)
    }
    var shape = parseKV(rest)
    shape["type"] = cmd
    let clearFirst = shape.removeValue(forKey: "clear_first")
    var req: [String: Any] = ["cmd": "draw", "shape": shape]
    if let c = clearFirst { req["clear_first"] = c }
    send(req)
}
