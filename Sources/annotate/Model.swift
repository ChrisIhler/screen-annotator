import AppKit

enum ShapeKind: String, CaseIterable {
    case circle, rect, highlight, arrow, label, marker, spotlight
}

/// A fully resolved annotation: geometry is in display-local points with a
/// top-left origin, ready to draw.
struct Annotation {
    let uid: Int                 // internal, unique
    let id: String               // caller-visible (may be shared, e.g. display "all")
    let kind: ShapeKind
    let displayID: CGDirectDisplayID
    let displayName: String
    var rect: CGRect = .zero     // circle / rect / highlight / spotlight / marker bounds
    var from: CGPoint = .zero    // arrow tail, label anchor
    var to: CGPoint = .zero      // arrow head
    var text: String?            // label/marker text
    var caption: String?         // optional label attached to any shape
    var color: NSColor
    var lineWidth: CGFloat
    var fillOpacity: CGFloat
    var opacity: CGFloat
    var fontSize: CGFloat
    var cornerRadius: CGFloat
    var dim: CGFloat
    var pinned: Bool
    var expiresAt: Date?

    private func r(_ v: CGFloat) -> Double { (Double(v) * 10).rounded() / 10 }

    var summary: [String: Any] {
        var d: [String: Any] = [
            "id": id, "type": kind.rawValue, "display": displayName,
            "pinned_to_space": pinned,
        ]
        switch kind {
        case .arrow:
            d["from"] = [r(from.x), r(from.y)]; d["to"] = [r(to.x), r(to.y)]
        case .label:
            d["at"] = [r(from.x), r(from.y)]
        default:
            d["bounds"] = [r(rect.minX), r(rect.minY), r(rect.width), r(rect.height)]
        }
        if let t = text { d["text"] = t }
        if let c = caption { d["label"] = c }
        if let e = expiresAt { d["expires_in_seconds"] = max(0, Int(e.timeIntervalSinceNow.rounded())) }
        return d
    }
}

// MARK: - Parsing

enum ShapeParser {
    private static var nextUID = 0
    private static var nextAutoID = 0

    static let urgencyColors: [String: (NSColor, String)] = [
        "urgent": (Palette.hex("#FF3B30")!, "🔴"),
        "soon": (Palette.hex("#FFCC00")!, "🟡"),
        "fyi": (Palette.hex("#0A84FF")!, "🔵"),
    ]

    /// Parse one shape dictionary. `defaults` supplies values the shape omits.
    /// Returns one annotation per targeted display.
    static func parse(_ shape: [String: Any], defaults: [String: Any]) throws -> [Annotation] {
        var s = defaults
        s.merge(shape) { _, new in new }

        guard let typeRaw = (s["type"] as? String)?.lowercased() else {
            throw AnnotatorError("Each shape needs a \"type\": one of \(ShapeKind.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let aliases = ["ellipse": "circle", "box": "rect", "rectangle": "rect", "text": "label", "badge": "marker", "number": "marker"]
        guard let kind = ShapeKind(rawValue: aliases[typeRaw] ?? typeRaw) else {
            throw AnnotatorError("Unknown shape type '\(typeRaw)'.")
        }

        let screens = try Displays.resolve(s["display"])
        let userID: String
        if let given = str(s, "id"), !given.isEmpty { userID = given }
        else { nextAutoID += 1; userID = "a\(nextAutoID)" }

        // Style
        var color = Palette.parse(str(s, "color")) ?? Palette.hex("#FF3B30")!
        var caption = str(s, "label").flatMap { $0.isEmpty ? nil : $0 }
        var text = str(s, "text")
        if let urg = (s["urgency"] as? String)?.lowercased() {
            guard let (c, emoji) = urgencyColors[urg] else {
                throw AnnotatorError("urgency must be one of: urgent, soon, fyi")
            }
            if s["color"] == nil { color = c }
            if let cap = caption, !cap.hasPrefix(emoji) { caption = "\(emoji) \(cap)" }
            if kind == .label, let t = text, !t.hasPrefix(emoji) { text = "\(emoji) \(t)" }
        }
        let duration = num(s, "duration_seconds") ?? num(s, "duration")
        let pinned = bool(s, "pin_to_current_space") ?? false

        var out: [Annotation] = []
        for screen in screens {
            let u = UnitScale(units: (s["units"] as? String) ?? "points", screen: screen)
            nextUID += 1
            var a = Annotation(
                uid: nextUID, id: userID, kind: kind,
                displayID: Displays.id(of: screen), displayName: screen.localizedName,
                text: text, caption: caption, color: color,
                lineWidth: CGFloat(num(s, "line_width") ?? 5),
                fillOpacity: CGFloat(num(s, "fill_opacity") ?? (kind == .highlight ? 0.28 : 0)),
                opacity: CGFloat(num(s, "opacity") ?? 1),
                fontSize: CGFloat(num(s, "font_size") ?? 20),
                cornerRadius: CGFloat(num(s, "corner_radius") ?? 10),
                dim: CGFloat(num(s, "dim") ?? 0.55),
                pinned: pinned,
                expiresAt: duration.flatMap { $0 > 0 ? Date().addingTimeInterval($0) : nil }
            )
            if kind == .highlight, s["color"] == nil, s["urgency"] == nil {
                a.color = Palette.hex("#FFD60A")!
            }

            switch kind {
            case .circle:
                let x = try need(s, "x"), y = try need(s, "y")
                if let r = num(s, "radius") {
                    let rr = r * u.r
                    a.rect = CGRect(x: x * u.x - rr, y: y * u.y - rr, width: rr * 2, height: rr * 2)
                } else if let w = num(s, "width"), let h = num(s, "height") {
                    // Circle *around* a box: pad so the ellipse clears the box corners.
                    let box = CGRect(x: x * u.x, y: y * u.y, width: w * u.x, height: h * u.y)
                    a.rect = box.insetBy(dx: -box.width * 0.2 - 8, dy: -box.height * 0.2 - 8)
                } else {
                    throw AnnotatorError("circle needs either radius (with x,y as center) or width+height (with x,y as the box's top-left).")
                }
            case .rect, .highlight, .spotlight:
                a.rect = CGRect(x: try need(s, "x") * u.x, y: try need(s, "y") * u.y,
                                width: try need(s, "width") * u.x, height: try need(s, "height") * u.y)
            case .arrow:
                a.from = CGPoint(x: try need(s, "from_x") * u.x, y: try need(s, "from_y") * u.y)
                a.to = CGPoint(x: try need(s, "to_x") * u.x, y: try need(s, "to_y") * u.y)
            case .label:
                guard let t = a.text, !t.isEmpty else { throw AnnotatorError("label needs \"text\".") }
                a.from = CGPoint(x: try need(s, "x") * u.x, y: try need(s, "y") * u.y)
                _ = t
            case .marker:
                let size = CGFloat(num(s, "size") ?? 40)
                let c = CGPoint(x: try need(s, "x") * u.x, y: try need(s, "y") * u.y)
                a.rect = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
                if let n = s["number"] { a.text = "\(n is NSNumber ? String((n as! NSNumber).intValue) : "\(n)")" }
                if a.text == nil || a.text!.isEmpty { throw AnnotatorError("marker needs \"number\" or \"text\".") }
            }
            out.append(a)
        }
        return out
    }

    static func str(_ d: [String: Any], _ k: String) -> String? {
        if let v = d[k] as? String { return v }
        if let n = d[k] as? NSNumber {
            let v = n.doubleValue
            return v == v.rounded() ? String(Int(v)) : "\(v)"
        }
        return nil
    }

    static func num(_ d: [String: Any], _ k: String) -> Double? {
        if let n = d[k] as? NSNumber { return n.doubleValue }
        if let s = d[k] as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func bool(_ d: [String: Any], _ k: String) -> Bool? {
        if let n = d[k] as? NSNumber { return n.boolValue }
        if let s = (d[k] as? String)?.lowercased() { return ["1", "true", "yes", "on"].contains(s) }
        return nil
    }

    private static func need(_ d: [String: Any], _ k: String) throws -> CGFloat {
        guard let v = num(d, k) else {
            throw AnnotatorError("\(d["type"] ?? "shape") is missing required number \"\(k)\".")
        }
        return CGFloat(v)
    }
}

/// Converts caller units to display points.
struct UnitScale {
    let x: CGFloat, y: CGFloat, r: CGFloat
    init(units: String, screen: NSScreen) {
        switch units.lowercased() {
        case "pixels", "px":
            let s = 1 / screen.backingScaleFactor
            x = s; y = s; r = s
        case "fraction", "fractions", "relative", "percent01":
            x = screen.frame.width; y = screen.frame.height
            r = min(screen.frame.width, screen.frame.height)
        default:
            x = 1; y = 1; r = 1
        }
    }
}

enum Palette {
    static let named: [String: String] = [
        "red": "#FF3B30", "orange": "#FF9500", "yellow": "#FFCC00", "green": "#34C759",
        "mint": "#00C7BE", "teal": "#30B0C7", "cyan": "#32ADE6", "blue": "#0A84FF",
        "indigo": "#5E5CE6", "purple": "#AF52DE", "pink": "#FF2D55", "magenta": "#FF00FF",
        "white": "#FFFFFF", "black": "#000000", "gray": "#8E8E93", "grey": "#8E8E93",
    ]

    static func parse(_ s: String?) -> NSColor? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if let h = named[s] { return hex(h) }
        return hex(s)
    }

    static func hex(_ raw: String) -> NSColor? {
        var s = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let r = CGFloat((v >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((v >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((v >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(v & 0xFF) / 255 : 1
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
