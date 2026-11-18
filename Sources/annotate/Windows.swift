import AppKit

/// App windows, from the window server. Owner (app) names and bounds need no
/// permission; window *titles* are only visible with Screen Recording access.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let title: String?
    let bounds: CGRect          // global, top-left origin at the main display (CG coordinates)

    var json: [String: Any] {
        var d: [String: Any] = [
            "window_id": Int(id), "app": owner,
            "bounds": [bounds.minX, bounds.minY, bounds.width, bounds.height],
        ]
        if let t = title, !t.isEmpty { d["title"] = t }
        if let s = Windows.screen(containing: bounds) {
            d["display"] = s.localizedName
            let tl = Windows.topLeft(of: s)
            d["display_bounds"] = [bounds.minX - tl.x, bounds.minY - tl.y, bounds.width, bounds.height]
        }
        return d
    }
}

enum Windows {
    /// Normal app windows currently on screen, front to back.
    static func list() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let me = getpid()
        return raw.compactMap { info(from: $0) }.filter { $0.pid != me }
    }

    static func info(from d: [String: Any]) -> WindowInfo? {
        guard (d[kCGWindowLayer as String] as? Int) == 0,
              let id = d[kCGWindowNumber as String] as? CGWindowID,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t,
              let bd = d[kCGWindowBounds as String] as? NSDictionary,
              let b = CGRect(dictionaryRepresentation: bd),
              b.width > 40, b.height > 40 else { return nil }
        return WindowInfo(id: id, pid: pid, owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                          title: d[kCGWindowName as String] as? String, bounds: b)
    }

    /// Current bounds of one window, or nil if it's closed, minimized or on another Space.
    static func bounds(of id: CGWindowID) -> CGRect? {
        guard let raw = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let d = raw.first, (d[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bd = d[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bd)
    }

    /// Resolve a selector: a window id number, "front"/"frontmost" (the active
    /// app's front window), or part of an app name or window title.
    static func resolve(_ selector: Any) throws -> WindowInfo {
        let all = list()
        if let n = selector as? NSNumber {
            if let w = all.first(where: { $0.id == n.uint32Value }) { return w }
            throw AnnotatorError("No on-screen window with id \(n).")
        }
        guard let raw = selector as? String, !raw.isEmpty else { throw AnnotatorError("window must be a name or id") }
        let s = raw.lowercased()
        if let n = UInt32(s), let w = all.first(where: { $0.id == n }) { return w }
        if ["front", "frontmost", "active", "focused"].contains(s) {
            if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               let w = all.first(where: { $0.pid == pid }) { return w }
            if let w = all.first { return w }
        }
        if let w = all.first(where: { $0.owner.lowercased() == s }) { return w }
        if let w = all.first(where: { $0.owner.lowercased().contains(s) }) { return w }
        if let w = all.first(where: { ($0.title ?? "").lowercased().contains(s) }) { return w }
        let apps = Array(Set(all.map(\.owner))).sorted().joined(separator: ", ")
        throw AnnotatorError("No visible window matches '\(raw)'. Apps with windows on screen: \(apps)")
    }

    /// Top-left corner of a display in CG global coordinates.
    static func topLeft(of screen: NSScreen) -> CGPoint {
        let mainMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGPoint(x: screen.frame.minX, y: mainMaxY - screen.frame.maxY)
    }

    /// The display holding most of a CG-global rect (by its center).
    static func screen(containing r: CGRect) -> NSScreen? {
        let c = CGPoint(x: r.midX, y: r.midY)
        return NSScreen.screens.first { s in
            CGRect(origin: topLeft(of: s), size: s.frame.size).contains(c)
        } ?? NSScreen.screens.first
    }
}
