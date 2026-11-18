import Foundation
import CoreGraphics

/// Interactive first-run tutorial. Draws on the display under the mouse
/// pointer and waits for the user to press the on-screen buttons, so a new
/// installer learns the marks and proves the overlay and clicks work.
enum Tutorial {
    struct Result { var steps: [String] = []; var completed = false }

    /// - Parameter say: where narration goes (stdout for the CLI, collected text for MCP).
    static func run(display: String = "mouse", stepTimeout: Double = 180, say: (String) -> Void) -> Result {
        var result = Result()
        func draw(_ shapes: [[String: Any]]) throws {
            let r = try Client.request(["cmd": "draw", "display": display, "units": "fraction",
                                        "clear_first": true, "shapes": shapes])
            if r["ok"] as? Bool != true { throw AnnotatorError("\(r["error"] ?? "draw failed")") }
        }
        func wait(_ id: String) throws -> String? {
            let deadline = Date().addingTimeInterval(stepTimeout)
            while Date() < deadline {
                if let e = try Client.request(["cmd": "events", "id": id])["event"] as? [String: Any] {
                    return e["action"] as? String
                }
                usleep(250_000)
            }
            return nil
        }
        func finish(_ msg: String) -> Result {
            _ = try? Client.request(["cmd": "clear"])
            say(msg)
            return result
        }

        do {
            let ping = try Client.request(["cmd": "ping"])
            say("Screen Annotator \(ping["version"] ?? "") is running. Look at the screen your mouse pointer is on.")
            _ = try Client.request(["cmd": "events", "consume": true]) // drain stale clicks

            // Step 1: buttons
            try draw([
                ["type": "spotlight", "x": 0.3, "y": 0.3, "width": 0.4, "height": 0.4, "dim": 0.35, "color": "white", "dismissible": false],
                ["type": "label", "x": 0.33, "y": 0.36, "text": "👋 Welcome to Screen Annotator", "color": "black", "font_size": 26, "dismissible": false],
                ["type": "marker", "x": 0.36, "y": 0.5, "number": 1, "urgency": "urgent", "id": "tut1",
                 "label": "Step 1: press the green button", "done_text": "Next", "dismissible": false],
            ])
            say("Step 1/4: press the green ✓ Next button on screen.")
            guard try wait("tut1") == "done" else { return finish("Tutorial stopped (no click on step 1). Run it again any time with: annotate tutorial") }
            result.steps.append("Clicking a ✓ button works")

            // Step 2: shapes + click-through
            try draw([
                ["type": "circle", "x": 0.2, "y": 0.3, "radius": 0.07, "urgency": "urgent", "label": "Circle", "dismissible": false],
                ["type": "arrow", "from_x": 0.35, "from_y": 0.2, "to_x": 0.48, "to_y": 0.38, "urgency": "soon", "label": "Arrow", "dismissible": false],
                ["type": "highlight", "x": 0.55, "y": 0.2, "width": 0.3, "height": 0.07, "label": "Highlight", "color": "yellow", "dismissible": false],
                ["type": "rect", "x": 0.15, "y": 0.55, "width": 0.25, "height": 0.2, "urgency": "fyi", "label": "Box", "dismissible": false],
                ["type": "marker", "x": 0.6, "y": 0.62, "number": 2, "urgency": "urgent", "id": "tut2",
                 "label": "Step 2: marks are see-through. Try clicking something under them, then press Next", "done_text": "Next", "dismissible": false],
            ])
            say("Step 2/4: these are the marks an AI can draw. Clicks pass through them to your apps. Press ✓ Next when ready.")
            guard try wait("tut2") == "done" else { return finish("Tutorial stopped at step 2.") }
            result.steps.append("Shapes draw and clicks pass through")

            // Step 3: dismiss
            try draw([
                ["type": "rect", "x": 0.35, "y": 0.4, "width": 0.3, "height": 0.15, "urgency": "fyi", "id": "tut3",
                 "label": "Step 3: close this one with the ✕ button"],
            ])
            say("Step 3/4: close the blue box with its small ✕ button.")
            guard try wait("tut3") != nil else { return finish("Tutorial stopped at step 3.") }
            result.steps.append("Dismissing with ✕ works")

            // Step 4: screen access info
            let canSee = CGPreflightScreenCaptureAccess()
            say(canSee
                ? "Step 4/4: Screen Recording is allowed for this app, so screenshots taken from here will show your windows."
                : "Step 4/4: Drawing needs no permission. For an AI to *see* your screen, the app that takes screenshots (for example Claude) needs Screen Recording permission: System Settings › Privacy & Security › Screen Recording.")
            try draw([
                ["type": "spotlight", "x": 0.3, "y": 0.35, "width": 0.4, "height": 0.25, "dim": 0.3, "color": "green", "dismissible": false],
                ["type": "label", "x": 0.33, "y": 0.42, "text": "✅ All set! An AI can now point at things for you.", "color": "green", "font_size": 24, "id": "tut4", "done_text": "Finish", "dismissible": false],
            ])
            _ = try wait("tut4")
            result.steps.append("Screen Recording for this app: \(canSee ? "allowed" : "not granted (only needed for screenshots)")")
            result.completed = true
            return finish("Tutorial complete. Connect it to your AI app with: annotate mcp  (see README).")
        } catch {
            return finish("Tutorial error: \(error)")
        }
    }
}
