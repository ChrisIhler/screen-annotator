import AppKit

/// A borderless, transparent, click-through window that covers one display.
final class OverlayWindow: NSWindow {
    let view = OverlayView()

    init(screen: NSScreen, allSpaces: Bool) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // clicks pass straight through
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .screenSaver               // above normal windows and the menu bar
        collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            : [.fullScreenAuxiliary, .ignoresCycle]   // stays on the Space it was shown on
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class OverlayView: NSView {
    var items: [Annotation] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }   // top-left origin, matches screenshots

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        // Spotlights first so other marks sit on top of the dimming.
        for a in items where a.kind == .spotlight { Renderer.draw(a, bounds: bounds) }
        for a in items where a.kind != .spotlight { Renderer.draw(a, bounds: bounds) }
    }
}

// MARK: - Drawing

enum Renderer {
    static func draw(_ a: Annotation, bounds: CGRect) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }
        ctx.cgContext.setAlpha(max(0, min(1, a.opacity)))

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        switch a.kind {
        case .circle:
            shadow.set()
            stroke(NSBezierPath(ovalIn: a.rect), a)
        case .rect:
            shadow.set()
            stroke(NSBezierPath(roundedRect: a.rect, xRadius: a.cornerRadius, yRadius: a.cornerRadius), a)
        case .highlight:
            let p = NSBezierPath(roundedRect: a.rect, xRadius: a.cornerRadius / 2, yRadius: a.cornerRadius / 2)
            a.color.withAlphaComponent(a.fillOpacity).setFill()
            p.fill()
            a.color.withAlphaComponent(0.9).setStroke()
            p.lineWidth = 2
            p.stroke()
        case .spotlight:
            let p = NSBezierPath(rect: bounds)
            p.append(NSBezierPath(roundedRect: a.rect, xRadius: a.cornerRadius, yRadius: a.cornerRadius))
            p.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(a.dim).setFill()
            p.fill()
            shadow.set()
            let ring = NSBezierPath(roundedRect: a.rect, xRadius: a.cornerRadius, yRadius: a.cornerRadius)
            a.color.setStroke(); ring.lineWidth = 3; ring.stroke()
        case .arrow:
            shadow.set()
            drawArrow(a)
        case .label:
            shadow.set()
            let (str, size) = pill(a.text ?? "", a)
            drawPill(str, in: clamp(CGRect(origin: a.from, size: size), to: bounds), a)
        case .marker:
            shadow.set()
            let p = NSBezierPath(ovalIn: a.rect)
            a.color.setFill(); p.fill()
            NSColor.white.setStroke(); p.lineWidth = 3; p.stroke()
            let font = NSFont.systemFont(ofSize: a.rect.height * 0.5, weight: .heavy)
            let str = NSAttributedString(string: a.text ?? "", attributes: [
                .font: font, .foregroundColor: textColor(on: a.color),
            ])
            let sz = str.size()
            NSShadow().set()
            str.draw(at: CGPoint(x: a.rect.midX - sz.width / 2, y: a.rect.midY - sz.height / 2))
        }

        if let cap = a.caption, a.kind != .label {
            shadow.set()
            let (str, size) = pill(cap, a)
            drawPill(str, in: captionRect(for: a, size: size, bounds: bounds), a)
        }
    }

    private static func stroke(_ p: NSBezierPath, _ a: Annotation) {
        if a.fillOpacity > 0 {
            a.color.withAlphaComponent(a.fillOpacity).setFill()
            p.fill()
        }
        a.color.setStroke()
        p.lineWidth = a.lineWidth
        p.lineJoinStyle = .round
        p.stroke()
    }

    private static func drawArrow(_ a: Annotation) {
        let dx = a.to.x - a.from.x, dy = a.to.y - a.from.y
        let len = max(hypot(dx, dy), 0.001)
        let ux = dx / len, uy = dy / len
        let head = min(max(22, a.lineWidth * 4.5), len * 0.6)
        let halfW = head * 0.55
        let base = CGPoint(x: a.to.x - ux * head, y: a.to.y - uy * head)

        let shaft = NSBezierPath()
        shaft.move(to: a.from)
        shaft.line(to: CGPoint(x: base.x + ux * 2, y: base.y + uy * 2))
        shaft.lineWidth = a.lineWidth
        shaft.lineCapStyle = .round
        a.color.setStroke()
        shaft.stroke()

        let tri = NSBezierPath()
        tri.move(to: a.to)
        tri.line(to: CGPoint(x: base.x - uy * halfW, y: base.y + ux * halfW))
        tri.line(to: CGPoint(x: base.x + uy * halfW, y: base.y - ux * halfW))
        tri.close()
        a.color.setFill()
        tri.fill()
    }

    // Label pills

    static func pill(_ text: String, _ a: Annotation) -> (NSAttributedString, CGSize) {
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: a.fontSize, weight: .bold),
            .foregroundColor: textColor(on: a.color),
        ])
        let s = str.size()
        return (str, CGSize(width: ceil(s.width) + a.fontSize * 1.1, height: ceil(s.height) + a.fontSize * 0.6))
    }

    private static func drawPill(_ str: NSAttributedString, in r: CGRect, _ a: Annotation) {
        let p = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        a.color.withAlphaComponent(0.95).setFill()
        p.fill()
        NSShadow().set()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        p.lineWidth = 1.5
        p.stroke()
        let s = str.size()
        str.draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
    }

    static func captionRect(for a: Annotation, size: CGSize, bounds: CGRect) -> CGRect {
        let gap: CGFloat = 8
        if a.kind == .arrow {
            // Put the caption at the arrow's tail, pushed away from the head.
            let dx = a.to.x - a.from.x, dy = a.to.y - a.from.y
            let len = max(hypot(dx, dy), 0.001)
            let push = (abs(dx / len) * size.width + abs(dy / len) * size.height) / 2 + gap
            let c = CGPoint(x: a.from.x - dx / len * push, y: a.from.y - dy / len * push)
            return clamp(CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height), to: bounds)
        }
        var r = CGRect(x: a.rect.minX, y: a.rect.minY - size.height - gap, width: size.width, height: size.height)
        if r.minY < bounds.minY + 4 { r.origin.y = a.rect.maxY + gap }      // no room above: go below
        if r.maxY > bounds.maxY - 4 { r.origin.y = a.rect.minY + gap }      // no room either: inside
        return clamp(r, to: bounds)
    }

    static func clamp(_ r: CGRect, to b: CGRect) -> CGRect {
        var o = r.origin
        o.x = min(max(o.x, b.minX + 4), b.maxX - r.width - 4)
        o.y = min(max(o.y, b.minY + 4), b.maxY - r.height - 4)
        return CGRect(origin: o, size: r.size)
    }

    private static func textColor(on c: NSColor) -> NSColor {
        guard let rgb = c.usingColorSpace(.sRGB) else { return .white }
        let lum = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return lum > 0.65 ? .black : .white
    }
}

// MARK: - Controller

/// Owns all annotations and the windows that show them. Main thread only.
final class Overlay {
    static let shared = Overlay()

    private(set) var annotations: [Annotation] = []
    private var displayWindows: [CGDirectDisplayID: OverlayWindow] = [:]
    private var pinnedWindows: [Int: OverlayWindow] = [:]   // keyed by uid
    private var controlPanels: [Int: ControlPanel] = [:]    // keyed by uid
    private(set) var events: [ClickEvent] = []
    private var nextSeq = 0
    var onChange: (() -> Void)?

    func add(_ list: [Annotation]) {
        annotations.append(contentsOf: list)
        for a in list {
            if a.pinned, let screen = Displays.screen(for: a.displayID) {
                let w = OverlayWindow(screen: screen, allSpaces: false)
                w.view.items = [a]
                w.orderFrontRegardless()
                pinnedWindows[a.uid] = w
            }
            if let exp = a.expiresAt {
                let uid = a.uid
                DispatchQueue.main.asyncAfter(deadline: .now() + exp.timeIntervalSinceNow) { [weak self] in
                    self?.remove { $0.uid == uid }
                }
            }
        }
        refresh()
        rebuildControls()
    }

    /// Remove matching annotations; returns how many were removed.
    @discardableResult
    func remove(where match: (Annotation) -> Bool) -> Int {
        let gone = annotations.filter(match)
        guard !gone.isEmpty else { return 0 }
        annotations.removeAll(where: match)
        for a in gone {
            if let w = pinnedWindows.removeValue(forKey: a.uid) { w.orderOut(nil); w.close() }
        }
        refresh()
        rebuildControls()
        return gone.count
    }

    func refresh() {
        let screens = NSScreen.screens
        let liveIDs = Set(screens.map(Displays.id(of:)))
        for (id, w) in displayWindows where !liveIDs.contains(id) {
            w.orderOut(nil); w.close(); displayWindows[id] = nil
        }
        for screen in screens {
            let id = Displays.id(of: screen)
            let items = annotations.filter { !$0.pinned && $0.displayID == id }
            if items.isEmpty {
                displayWindows[id]?.orderOut(nil)
                displayWindows[id]?.view.items = []
                continue
            }
            let w = displayWindows[id] ?? OverlayWindow(screen: screen, allSpaces: true)
            displayWindows[id] = w
            if w.frame != screen.frame { w.setFrame(screen.frame, display: false) }
            w.view.items = items
            w.orderFrontRegardless()
        }
        onChange?()
    }

    func screensChanged() {
        for (uid, w) in pinnedWindows {
            if let a = annotations.first(where: { $0.uid == uid }), let s = Displays.screen(for: a.displayID) {
                w.setFrame(s.frame, display: true)
            }
        }
        refresh()
        rebuildControls()
    }

    // MARK: Clickable controls

    /// One button strip per (id, display): the first annotation of a group
    /// carries it, so a multi-shape action gets a single Done button.
    private func rebuildControls() {
        var wanted: [Int: Annotation] = [:]
        var seen = Set<String>()
        for a in annotations where a.task || a.dismissible {
            let key = "\(a.id)|\(a.displayID)"
            if seen.insert(key).inserted { wanted[a.uid] = a }
        }
        for (uid, p) in controlPanels where wanted[uid] == nil {
            p.orderOut(nil); p.close(); controlPanels[uid] = nil
        }
        for (uid, a) in wanted where controlPanels[uid] == nil {
            guard let screen = Displays.screen(for: a.displayID) else { continue }
            let view = ControlsView()
            var specs: [(String, NSColor, NSColor, () -> Void)] = []
            let id = a.id, did = a.displayID
            if a.task {
                specs.append(("✓ \(a.doneText)", Palette.hex("#34C759")!, .white, { [weak self] in
                    self?.clicked(id: id, displayID: did, action: "done")
                }))
            }
            if a.dismissible {
                specs.append(("✕", NSColor(white: 0.15, alpha: 0.85), .white, { [weak self] in
                    self?.clicked(id: id, displayID: did, action: "dismissed")
                }))
            }
            let size = view.configure(specs)
            let local = Renderer.controlsRect(for: a, size: size, bounds: CGRect(origin: .zero, size: screen.frame.size))
            let global = CGRect(x: screen.frame.minX + local.minX, y: screen.frame.maxY - local.maxY,
                                width: size.width, height: size.height)
            let panel = ControlPanel(frame: global, allSpaces: !a.pinned, content: view)
            view.frame = CGRect(origin: .zero, size: size)
            panel.orderFrontRegardless()
            controlPanels[uid] = panel
        }
    }

    func clicked(id: String, displayID: CGDirectDisplayID, action: String) {
        let group = annotations.filter { $0.id == id && $0.displayID == displayID }
        guard let first = group.first else { return }
        nextSeq += 1
        events.append(ClickEvent(seq: nextSeq, id: id, action: action, display: first.displayName,
                                 label: first.caption ?? first.text, at: Date()))
        if events.count > 500 { events.removeFirst(events.count - 500) }

        if action == "done" {
            // Brief green "✓ Done" confirmation, then remove.
            let uids = Set(group.map(\.uid))
            for i in annotations.indices where uids.contains(annotations[i].uid) {
                annotations[i].color = Palette.hex("#34C759")!
                if annotations[i].kind == .label { annotations[i].text = "✓ \(first.doneText)" }
                else { annotations[i].caption = "✓ \(first.doneText)" }
                annotations[i].task = false
                annotations[i].dismissible = false
            }
            for (uid, w) in pinnedWindows where uids.contains(uid) {
                w.view.items = annotations.filter { $0.uid == uid }
            }
            refresh()
            rebuildControls()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.remove { uids.contains($0.uid) }
            }
        } else {
            remove { $0.id == id && $0.displayID == displayID }
        }
    }

    /// Return (and by default consume) the oldest unread click, optionally for one id.
    func takeEvent(id: String?, consume: Bool) -> ClickEvent? {
        guard let i = events.firstIndex(where: { !$0.consumed && (id == nil || $0.id == id) }) else { return nil }
        if consume { events[i].consumed = true }
        return events[i]
    }
}
