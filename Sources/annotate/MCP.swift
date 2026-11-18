import Foundation

/// A minimal Model Context Protocol server over stdio (newline-delimited
/// JSON-RPC 2.0). Every tool call is forwarded to the overlay daemon.
enum MCPServer {
    static let instructions = """
    Draws annotations (circles, arrows, boxes, highlights, numbered markers, labels, spotlights) \
    on top of the user's screens in a transparent, click-through overlay. Call list_displays first \
    to learn each display's name, position (e.g. upper-left) and size. Coordinates are in points \
    from the top-left corner of the chosen display unless units says otherwise: units="fraction" \
    takes 0-1 values (best when working from a scaled screenshot), units="pixels" takes physical \
    pixels (Retina screenshots). Use urgency (urgent=🔴 red, soon=🟡 yellow, fyi=🔵 blue) to color-code \
    numbered actions. Annotations stay until cleared unless duration_seconds is set. Always clear \
    annotations when you are done pointing at things.
    """

    static func run() -> Never {
        setvbuf(stdout, nil, _IONBF, 0)
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                }
                continue
            }
            guard let id = msg["id"], !(id is NSNull) else { continue }   // notification
            let method = msg["method"] as? String ?? ""
            let params = msg["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                send(result(id, [
                    "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "screen-annotator", "version": annotatorVersion],
                    "instructions": instructions,
                ]))
            case "ping":
                send(result(id, [:]))
            case "tools/list":
                send(result(id, ["tools": Tools.all]))
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                send(result(id, call(name, args)))
            default:
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
            }
        }
        exit(0)
    }

    private static func call(_ name: String, _ args: [String: Any]) -> [String: Any] {
        guard let req = Tools.request(for: name, args) else {
            return toolText("Unknown tool '\(name)'.", isError: true)
        }
        do {
            let resp = try Client.request(req)
            let ok = resp["ok"] as? Bool ?? false
            var body = resp; body["ok"] = nil
            let text = ok
                ? String(data: (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data(), encoding: .utf8) ?? "ok"
                : "Error: \(resp["error"] ?? "unknown error")"
            return toolText(text, isError: !ok)
        } catch {
            return toolText("Error: \(error)", isError: true)
        }
    }

    private static func toolText(_ s: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": s]], "isError": isError]
    }

    private static func result(_ id: Any, _ r: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": r]
    }

    private static func send(_ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

// MARK: - Tool catalogue

enum Tools {
    private static func n(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
    private static func s(_ d: String) -> [String: Any] { ["type": "string", "description": d] }

    static let common: [String: Any] = [
        "display": s("Which display: index from list_displays (\"0\"), a name fragment (\"HDR\", \"ultrawide\", \"built-in\"), \"left\", \"right\", \"top\", \"bottom\", \"main\", \"mouse\" (display under the pointer) or \"all\". Default: main display."),
        "units": ["type": "string", "enum": ["points", "pixels", "fraction"], "description": "Coordinate units. points (default) = display points from its top-left; pixels = physical pixels (Retina screenshots); fraction = 0-1 of the display's width/height."],
        "color": s("Color name (red, orange, yellow, green, blue, purple, pink, white, black, gray...) or hex #RRGGBB / #RRGGBBAA. Default red."),
        "urgency": ["type": "string", "enum": ["urgent", "soon", "fyi"], "description": "Color-code: urgent=🔴 red, soon=🟡 yellow, fyi=🔵 blue. Also prefixes the label with that emoji."],
        "label": s("Optional text pill attached to the shape, e.g. \"Action 1: click Save\"."),
        "id": s("Optional id so you can clear just this annotation later. Auto-generated if omitted."),
        "line_width": n("Stroke width in points. Default 5."),
        "opacity": n("Overall opacity 0-1. Default 1."),
        "font_size": n("Label font size in points. Default 20."),
        "duration_seconds": n("Auto-clear after this many seconds. Omit to keep until cleared."),
        "pin_to_current_space": ["type": "boolean", "description": "true = show only on the macOS desktop (Space) that is active right now. Default false = visible on every desktop."],
        "clear_first": ["type": "boolean", "description": "Clear existing annotations on the target display(s) before drawing."],
    ]

    private static func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String], withCommon: Bool = true) -> [String: Any] {
        var p = withCommon ? common : [:]
        p.merge(props) { _, new in new }
        return ["name": name, "description": desc,
                "inputSchema": ["type": "object", "properties": p, "required": required]]
    }

    static let shapeTools: [String: String] = [
        "draw_circle": "circle", "draw_rect": "rect", "highlight": "highlight",
        "draw_arrow": "arrow", "label": "label", "marker": "marker", "spotlight": "spotlight",
    ]

    static var all: [[String: Any]] {
        let box: [String: Any] = [
            "x": n("Left edge of the box."), "y": n("Top edge of the box."),
            "width": n("Box width."), "height": n("Box height."),
        ]
        var shapeItem = common
        shapeItem["type"] = ["type": "string", "enum": ShapeKind.allCases.map(\.rawValue)]
        for k in ["clear_first"] { shapeItem[k] = nil }
        return [
            tool("list_displays", "List connected displays with index, name, physical position (upper-left, lower-right...), size in points, Retina scale, and which one has the mouse pointer. Call this before drawing.", [:], required: [], withCommon: false),
            tool("draw_circle", "Circle a spot or region. Either give x,y as the CENTER plus radius, or give x,y,width,height of a BOX and an ellipse is drawn around it with padding.", [
                "x": n("Center x (with radius) or box left (with width/height)."),
                "y": n("Center y (with radius) or box top (with width/height)."),
                "radius": n("Circle radius."), "width": n("Box width to circle."), "height": n("Box height to circle."),
            ], required: ["x", "y"]),
            tool("draw_rect", "Draw a rectangle outline around a region.", box.merging(["corner_radius": n("Corner radius. Default 10."), "fill_opacity": n("0-1 fill. Default 0 (outline only).")]) { $1 }, required: ["x", "y", "width", "height"]),
            tool("highlight", "Translucent highlighter box over a region (yellow by default).", box.merging(["fill_opacity": n("0-1. Default 0.28.")]) { $1 }, required: ["x", "y", "width", "height"]),
            tool("draw_arrow", "Draw an arrow from a tail point to a head point. A label is placed at the tail.", [
                "from_x": n("Tail x."), "from_y": n("Tail y."), "to_x": n("Head x (what it points at)."), "to_y": n("Head y."),
            ], required: ["from_x", "from_y", "to_x", "to_y"]),
            tool("label", "Place a text pill. x,y is its top-left corner. Emoji are fine (\"🔴 Action 1\").", [
                "x": n("Left."), "y": n("Top."), "text": s("Label text."),
            ], required: ["x", "y", "text"]),
            tool("marker", "Numbered badge (filled circle with a number) centered at x,y — good for step 1, 2, 3.", [
                "x": n("Center x."), "y": n("Center y."), "number": ["type": "integer", "description": "Number to show."],
                "text": s("Short text instead of a number."), "size": n("Diameter. Default 40."),
            ], required: ["x", "y"]),
            tool("spotlight", "Dim the whole display except one region to focus attention there.", box.merging(["dim": n("Darkness of the dimmed area 0-1. Default 0.55.")]) { $1 }, required: ["x", "y", "width", "height"]),
            tool("annotate", "Draw several shapes in one call. Top-level options (display, units, urgency, duration_seconds, clear_first...) apply to every shape unless the shape overrides them.", [
                "shapes": ["type": "array", "description": "Shapes. Each needs \"type\" (circle, rect, highlight, arrow, label, marker, spotlight) plus that shape's fields.",
                           "items": ["type": "object", "properties": shapeItem, "required": ["type"], "additionalProperties": true]],
            ], required: ["shapes"]),
            tool("clear", "Remove annotations. No arguments = clear everything. Give id and/or display to clear selectively.", [
                "id": s("Only clear annotations with this id."),
                "display": s("Only clear this display (same selectors as drawing)."),
            ], required: [], withCommon: false),
            tool("list_annotations", "List annotations currently on screen.", [:], required: [], withCommon: false),
        ]
    }

    /// Map a tool call to a daemon request.
    static func request(for name: String, _ args: [String: Any]) -> [String: Any]? {
        switch name {
        case "list_displays": return ["cmd": "list_displays"]
        case "list_annotations": return ["cmd": "list"]
        case "clear":
            var r = args; r["cmd"] = "clear"; return r
        case "annotate":
            var r = args; r["cmd"] = "draw"; return r
        default:
            guard let type = shapeTools[name] else { return nil }
            var shape = args
            shape["type"] = type
            let clearFirst = shape.removeValue(forKey: "clear_first")
            var r: [String: Any] = ["cmd": "draw", "shape": shape]
            if let c = clearFirst { r["clear_first"] = c }
            return r
        }
    }
}
