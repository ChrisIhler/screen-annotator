import Foundation
import Darwin

/// Talks to the overlay daemon, starting it on demand.
enum Client {
    static func request(_ req: [String: Any], autostart: Bool = true) throws -> [String: Any] {
        var fd = try? connectSocket()
        if fd == nil && autostart {
            try spawnDaemon()
            for _ in 0..<60 {                       // wait up to ~3 s
                usleep(50_000)
                if let f = try? connectSocket() { fd = f; break }
            }
        }
        guard let sock = fd else {
            throw AnnotatorError("The overlay daemon is not running and could not be started (\(socketPath)).")
        }
        defer { close(sock) }

        var data = try JSONSerialization.data(withJSONObject: req)
        data.append(0x0A)
        try data.withUnsafeBytes { p in
            var off = 0
            while off < data.count {
                let w = write(sock, p.baseAddress! + off, data.count - off)
                if w <= 0 { throw AnnotatorError("write to daemon failed") }
                off += w
            }
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while buffer.firstIndex(of: 0x0A) == nil {
            let n = read(sock, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
        }
        let line = buffer.prefix { $0 != 0x0A }
        guard let obj = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw AnnotatorError("Daemon returned an invalid response.")
        }
        return obj
    }

    private static func connectSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AnnotatorError("socket() failed") }
        var addr = makeAddr(socketPath)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if rc != 0 { close(fd); throw AnnotatorError("connect failed") }
        return fd
    }

    /// Launch `annotate daemon` detached in its own session so it outlives
    /// the CLI or MCP process that started it.
    private static func spawnDaemon() throws {
        let exe = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        var attr = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        var pid: pid_t = 0
        let args = [exe, "daemon"]
        var cargs = args.map { strdup($0) } + [nil]
        defer { cargs.forEach { free($0) } }
        let rc = posix_spawn(&pid, exe, &actions, &attr, &cargs, environ)
        if rc != 0 { throw AnnotatorError("Could not start daemon (posix_spawn error \(rc)).") }
    }
}
