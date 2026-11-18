// Test helper: opens a window titled "annotate-test-window" on the main display,
// moves it right by 200 pt after 2 s, minimizes it at 4 s, and exits at 6 s.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                 styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
w.title = "annotate-test-window"
w.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 2) { w.setFrameOrigin(NSPoint(x: 400, y: 200)) }
DispatchQueue.main.asyncAfter(deadline: .now() + 4) { w.orderOut(nil) }
DispatchQueue.main.asyncAfter(deadline: .now() + 6) { exit(0) }
app.run()
