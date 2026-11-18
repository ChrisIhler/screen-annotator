import AppKit
import Darwin

let annotatorVersion = "0.3.0"

/// Path of the local control socket. Only the current user can connect (0600).
let socketPath = "/tmp/screen-annotator-\(getuid()).sock"

// MARK: - Request handling (shared by the daemon; runs on the main thread)

enum Commands {
    static func handle(_ req: [String: Any]) -> [String: Any] {
        do {
            let cmd = (req["cmd"] as? String ?? "").lowercased()
            switch cmd {
            case "ping":
                return ["ok": true, "version": annotatorVersion, "annotations": Overlay.shared.annotations.count]
            case "list_displays", "displays":
                return ["ok": true, "displays": Displays.describe()]
            case "draw":
                return try draw(req)
            case "clear":
                return try clear(req)
            case "list", "list_annotations":
                return ["ok": true, "annotations": Overlay.shared.annotations.map(\.summary), "guides": Guides.shared.status]
            case "events", "take_event":
                let id = (req["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let consume = ShapeParser.bool(req, "consume") ?? true
                if let e = Overlay.shared.takeEvent(id: id, consume: consume) {
                    return ["ok": true, "event": e.json]
                }
                return ["ok": true, "event": NSNull()]
            case "list_windows", "windows":
                return ["ok": true, "windows": Windows.list().map(\.json),
                        "note": "Window titles appear only if this app has Screen Recording permission; app names always do."]
            case "guide":
                return try Guides.shared.start(req)
            case "_simulate_click":   // used by the test suite
                guard let id = req["id"] as? String,
                      let a = Overlay.shared.annotations.first(where: { $0.id == id }) else {
                    throw AnnotatorError("No annotation with that id.")
                }
                Overlay.shared.clicked(id: id, displayID: a.displayID, action: (req["action"] as? String) ?? "done")
                return ["ok": true]
            case "quit":
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
                return ["ok": true, "message": "Overlay daemon is quitting."]
            default:
                throw AnnotatorError("Unknown cmd '\(cmd)'. Use ping, list_displays, draw, clear, list, events or quit.")
            }
        } catch {
            return ["ok": false, "error": "\(error)"]
        }
    }

    private static func draw(_ req: [String: Any]) throws -> [String: Any] {
        var shapes = req["shapes"] as? [[String: Any]] ?? []
        if let one = req["shape"] as? [String: Any] { shapes.append(one) }
        guard !shapes.isEmpty else { throw AnnotatorError("draw needs \"shapes\" (array) or \"shape\" (object).") }

        var defaults = req
        for k in ["cmd", "shapes", "shape", "clear_first"] { defaults[k] = nil }

        // Parse everything first so a bad shape draws nothing (all-or-nothing).
        var parsed: [Annotation] = []
        for s in shapes { parsed += try ShapeParser.parse(s, defaults: defaults) }

        let clearFirst = ShapeParser.bool(req, "clear_first") ?? shapes.contains { ShapeParser.bool($0, "clear_first") == true }
        if clearFirst {
            let targets = Set(parsed.map(\.displayID))
            Overlay.shared.remove { targets.contains($0.displayID) }
        }
        Overlay.shared.add(parsed)
        return ["ok": true, "drawn": parsed.map(\.summary)]
    }

    private static func clear(_ req: [String: Any]) throws -> [String: Any] {
        let id = (req["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var displays: Set<CGDirectDisplayID>? = nil
        if let sel = req["display"], !((sel as? String)?.isEmpty ?? false) {
            displays = Set(try Displays.resolve(sel).map(Displays.id(of:)))
        }
        if id == nil && displays == nil { Guides.shared.cancelAll() }
        if let id { Guides.shared.cancel(id, record: false) }
        let n = Overlay.shared.remove { a in
            (id == nil || a.id == id) && (displays == nil || displays!.contains(a.displayID))
        }
        return ["ok": true, "cleared": n, "remaining": Overlay.shared.annotations.count]
    }
}

// MARK: - Socket server

/// Newline-delimited JSON over a Unix domain socket. Each line is one request;
/// each request gets one JSON line back.
final class SocketServer {
    private var fd: Int32 = -1

    func start() throws {
        unlink(socketPath)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AnnotatorError("socket() failed: \(errno)") }
        var addr = makeAddr(socketPath)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard rc == 0 else { throw AnnotatorError("bind(\(socketPath)) failed: \(String(cString: strerror(errno)))") }
        chmod(socketPath, 0o600)
        guard listen(fd, 16) == 0 else { throw AnnotatorError("listen() failed") }

        let t = Thread { [fd] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                Thread { SocketServer.serve(client) }.start()
            }
        }
        t.start()
    }

    private static func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(chunk, count: n)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if line.isEmpty { continue }
                let response: [String: Any]
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    response = DispatchQueue.main.sync { Commands.handle(obj) }
                } else {
                    response = ["ok": false, "error": "Request was not a JSON object."]
                }
                var out = (try? JSONSerialization.data(withJSONObject: response)) ?? Data("{\"ok\":false}".utf8)
                out.append(0x0A)
                out.withUnsafeBytes { p in
                    var off = 0
                    while off < out.count {
                        let w = write(client, p.baseAddress! + off, out.count - off)
                        if w <= 0 { return }
                        off += w
                    }
                }
            }
        }
    }
}

func makeAddr(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8.prefix(103))
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        for (i, b) in bytes.enumerated() { raw[i] = b }
        raw[bytes.count] = 0
    }
    return addr
}

// MARK: - Daemon app

final class DaemonDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let countItem = NSMenuItem(title: "No annotations", action: nil, keyEquivalent: "")
    private let server = SocketServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try server.start() } catch {
            FileHandle.standardError.write(Data("annotate daemon: \(error)\n".utf8))
            exit(1)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "Screen Annotator") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "✎"
        }
        let menu = NSMenu()
        countItem.isEnabled = false
        menu.addItem(countItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear all annotations", action: #selector(clearAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit Screen Annotator", action: #selector(quit), keyEquivalent: "").target = self
        item.menu = menu
        statusItem = item

        Overlay.shared.onChange = { [weak self] in
            let n = Overlay.shared.annotations.count
            self?.countItem.title = n == 0 ? "No annotations" : "\(n) annotation\(n == 1 ? "" : "s") on screen"
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in Overlay.shared.screensChanged() }
    }

    func applicationWillTerminate(_ notification: Notification) { unlink(socketPath) }

    @objc private func clearAll() { Guides.shared.cancelAll(); Overlay.shared.remove { _ in true } }
    @objc private func quit() { NSApp.terminate(nil) }
}

func runDaemon() -> Never {
    if (try? Client.request(["cmd": "ping"], autostart: false)) != nil {
        print("annotate daemon is already running (\(socketPath)).")
        exit(0)
    }
    signal(SIGPIPE, SIG_IGN)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)   // no Dock icon, never steals focus
    let delegate = DaemonDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}
