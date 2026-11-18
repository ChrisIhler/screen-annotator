import AppKit

/// Display discovery and selector resolution.
///
/// All coordinates exposed to callers are *display-local*: the origin is the
/// top-left corner of the chosen display, x grows right, y grows down, and the
/// unit is macOS points (the "looks like" resolution in System Settings).
enum Displays {
    static func id(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { Self.id(of: $0) == id }
    }

    /// Union of all display frames (Cocoa global coordinates, y up).
    private static func union() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Human-friendly position such as "upper-left" or "lower-right".
    static func position(of screen: NSScreen) -> String {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return "only" }
        let u = union()
        let f = screen.frame
        let tolX = u.width * 0.1, tolY = u.height * 0.1
        let h: String = f.midX < u.midX - tolX ? "left" : (f.midX > u.midX + tolX ? "right" : "center")
        // Cocoa y grows upward, so a larger midY means physically higher.
        let v: String = f.midY > u.midY + tolY ? "upper" : (f.midY < u.midY - tolY ? "lower" : "")
        if v.isEmpty { return h }
        if h == "center" { return v == "upper" ? "top" : "bottom" }
        return "\(v)-\(h)"
    }

    static func describe() -> [[String: Any]] {
        let main = NSScreen.screens.first
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.enumerated().map { i, s in
            let f = s.frame
            return [
                "index": i,
                "id": Int(id(of: s)),
                "name": s.localizedName,
                "position": position(of: s),
                "is_main": s == main,
                "has_mouse": f.contains(mouse),
                "width": f.width,
                "height": f.height,
                "scale": s.backingScaleFactor,
                "pixel_width": f.width * s.backingScaleFactor,
                "pixel_height": f.height * s.backingScaleFactor,
                // Global origin of this display's top-left corner, in a
                // top-left-origin space anchored at the main display.
                "global_x": f.minX,
                "global_y": (main?.frame.maxY ?? f.maxY) - f.maxY,
            ]
        }
    }

    /// Resolve a selector to one or more screens.
    ///
    /// Accepts: an index (0, "1"), "id:<displayID>", "main"/"primary",
    /// "all", "mouse"/"cursor", "left"/"right"/"top"/"bottom" (by physical
    /// arrangement), or any case-insensitive substring of the display name
    /// ("HDR", "ultrawide", "built-in").
    static func resolve(_ selector: Any?) throws -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw AnnotatorError("No displays are connected.") }
        guard let selector else { return [screens[0]] }

        if let n = selector as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            return [try byIndex(n.intValue)]
        }
        guard let raw = selector as? String else { throw AnnotatorError("display must be a string or number") }
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty || s == "main" || s == "primary" || s == "default" { return [screens[0]] }
        if s == "all" { return screens }
        if let n = Int(s) { return [try byIndex(n)] }
        if s.hasPrefix("id:"), let n = UInt32(s.dropFirst(3)), let sc = screen(for: n) { return [sc] }
        switch s {
        case "mouse", "cursor", "pointer":
            let p = NSEvent.mouseLocation
            return [screens.first { $0.frame.contains(p) } ?? screens[0]]
        case "left", "leftmost": return [screens.min { $0.frame.midX < $1.frame.midX }!]
        case "right", "rightmost": return [screens.max { $0.frame.midX < $1.frame.midX }!]
        case "top", "upper", "topmost": return [screens.max { $0.frame.midY < $1.frame.midY }!]
        case "bottom", "lower", "bottommost": return [screens.min { $0.frame.midY < $1.frame.midY }!]
        case "builtin", "built-in", "laptop", "internal":
            if let b = screens.first(where: { CGDisplayIsBuiltin(id(of: $0)) != 0 }) { return [b] }
        default: break
        }
        // Exact position label ("upper-left") or name substring.
        if let p = screens.first(where: { position(of: $0) == s }) { return [p] }
        let matches = screens.filter { $0.localizedName.lowercased().contains(s) }
        if matches.count == 1 { return matches }
        if matches.count > 1 {
            throw AnnotatorError("display '\(raw)' matches several displays: \(matches.map(\.localizedName).joined(separator: ", ")). Use an index from list_displays.")
        }
        throw AnnotatorError("No display matches '\(raw)'. Available: " +
            screens.enumerated().map { "\($0.offset)=\($0.element.localizedName) (\(position(of: $0.element)))" }.joined(separator: ", "))
    }

    private static func byIndex(_ i: Int) throws -> NSScreen {
        let screens = NSScreen.screens
        guard screens.indices.contains(i) else {
            throw AnnotatorError("Display index \(i) is out of range (0...\(screens.count - 1)).")
        }
        return screens[i]
    }
}

struct AnnotatorError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
