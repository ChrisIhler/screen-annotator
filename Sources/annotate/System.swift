import AppKit
import Carbon.HIToolbox

// MARK: - Global "clear all" shortcut (⌃⌥⌘C)
//
// Uses Carbon's RegisterEventHotKey, which needs no Accessibility permission.

enum Hotkey {
    static let display = "⌃⌥⌘C"
    private static var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    static func register(_ handler: @escaping () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x414E4E54) /* 'ANNT' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(cmdKey | optionKey | controlKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - Start at login (a per-user LaunchAgent; no admin rights)

enum LoginItem {
    static let label = "io.github.chrisihler.screen-annotator"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func enable() throws {
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "daemon"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    static func disable() throws {
        if isEnabled { try FileManager.default.removeItem(at: plistURL) }
    }
}
