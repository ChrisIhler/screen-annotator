import AppKit

/// Small clickable button strip ("✓ Done", "✕") attached to an annotation.
///
/// The drawing overlay stays fully click-through; only these little panels
/// accept clicks. They are non-activating, so clicking them never steals
/// focus from the app you're working in.
final class ControlPanel: NSPanel {
    init(frame: NSRect, allSpaces: Bool, content: NSView) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            : [.fullScreenAuxiliary, .ignoresCycle]
        contentView = content
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class ControlsView: NSView {
    struct Button {
        var rect: CGRect
        let title: String
        let fill: NSColor
        let text: NSColor
        let action: () -> Void
    }

    static let height: CGFloat = 30
    static let gap: CGFloat = 6
    private static let font = NSFont.systemFont(ofSize: 14, weight: .semibold)

    private(set) var buttons: [Button] = []
    private var pressed: Int?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Lay out buttons left to right; returns the strip's total size.
    func configure(_ specs: [(String, NSColor, NSColor, () -> Void)]) -> CGSize {
        var x: CGFloat = 0
        buttons = specs.map { title, fill, text, action in
            let w = title == "✕"
                ? Self.height
                : ceil(NSAttributedString(string: title, attributes: [.font: Self.font]).size().width) + 24
            defer { x += w + Self.gap }
            return Button(rect: CGRect(x: x, y: 0, width: w, height: Self.height), title: title, fill: fill, text: text, action: action)
        }
        return CGSize(width: max(0, x - Self.gap), height: Self.height)
    }

    override func resetCursorRects() {
        for b in buttons { addCursorRect(b.rect, cursor: .pointingHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        dirtyRect.fill(using: .copy)
        for (i, b) in buttons.enumerated() {
            let r = b.rect.insetBy(dx: 1, dy: 1)
            let p = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
            (pressed == i ? b.fill.blended(withFraction: 0.3, of: .black)! : b.fill).setFill()
            p.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            p.lineWidth = 1.5
            p.stroke()
            let str = NSAttributedString(string: b.title, attributes: [.font: Self.font, .foregroundColor: b.text])
            let s = str.size()
            str.draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
        }
    }

    private func hit(_ e: NSEvent) -> Int? {
        let p = convert(e.locationInWindow, from: nil)
        return buttons.firstIndex { $0.rect.contains(p) }
    }

    override func mouseDown(with e: NSEvent) { pressed = hit(e); needsDisplay = true }

    override func mouseUp(with e: NSEvent) {
        let was = pressed
        pressed = nil
        needsDisplay = true
        if let i = was, hit(e) == i { buttons[i].action() }
    }
}

/// Something the user did by clicking an annotation's button.
struct ClickEvent {
    let seq: Int
    let id: String
    let action: String      // "done" or "dismissed"
    let display: String
    let label: String?
    let at: Date
    var consumed = false

    var json: [String: Any] {
        var d: [String: Any] = [
            "id": id, "action": action, "display": display,
            "at": ISO8601DateFormatter().string(from: at),
            "seconds_ago": Int(Date().timeIntervalSince(at).rounded()),
        ]
        if let l = label { d["label"] = l }
        return d
    }
}

extension Renderer {
    /// Where to put an annotation's buttons, in its display's flipped
    /// (top-left origin) coordinates.
    static func controlsRect(for a: Annotation, size: CGSize, bounds: CGRect) -> CGRect {
        let gap: CGFloat = 6
        var anchor: CGRect?
        if a.kind == .label {
            anchor = CGRect(origin: a.from, size: pill(a.text ?? "", a).1)
            anchor = anchor.map { clamp($0, to: bounds) }
        } else if let cap = a.caption {
            anchor = captionRect(for: a, size: pill(cap, a).1, bounds: bounds)
        }
        if let c = anchor {
            // Beside the label pill: right if there's room, else left.
            var r = CGRect(x: c.maxX + gap, y: c.midY - size.height / 2, width: size.width, height: size.height)
            if r.maxX > bounds.maxX - 4 { r.origin.x = c.minX - gap - size.width }
            return clamp(r, to: bounds)
        }
        let box: CGRect = a.kind == .arrow
            ? CGRect(x: min(a.from.x, a.to.x), y: min(a.from.y, a.to.y), width: abs(a.to.x - a.from.x), height: abs(a.to.y - a.from.y))
            : a.rect
        var r = CGRect(x: box.maxX - size.width, y: box.minY - size.height - gap, width: size.width, height: size.height)
        if r.minY < bounds.minY + 4 { r.origin.y = box.maxY + gap }
        return clamp(r, to: bounds)
    }
}
