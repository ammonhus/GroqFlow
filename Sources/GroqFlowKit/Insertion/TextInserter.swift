import AppKit
import CoreGraphics
import Carbon

// Places formatted text at the cursor by swapping the pasteboard and
// synthesizing Cmd-V, then restoring the user's clipboard. Falls back to
// typing unicode directly when the user prefers, and refuses to synthesize
// while secure input is active (would silently fail).
@MainActor
public enum TextInserter {

    // MARK: Public API

    public static func paste(_ text: String, typeInstead: Bool) {
        guard !text.isEmpty else { return }

        // Secure input (password fields, some terminals) blocks synthesized
        // events. Leave the text on the clipboard so the user can paste manually.
        if isSecureInputActive {
            writeTextConcealed(text)
            return
        }

        if typeInstead {
            typeText(text)
            return
        }

        let snapshot = snapshotPasteboard()
        writeTextConcealed(text)
        synthesizeCommandKey(9) // 'v'

        // Restore after the target app has had time to read the pasteboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            restorePasteboard(snapshot)
        }
    }

    public static func copySelection() async -> String? {
        let pb = NSPasteboard.general
        let snapshot = snapshotPasteboard()

        pb.clearContents()
        let afterClear = pb.changeCount

        synthesizeCommandKey(8) // 'c'
        try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms

        let didChange = pb.changeCount != afterClear
        let copied = pb.string(forType: .string)

        restorePasteboard(snapshot)

        if didChange, let copied, !copied.isEmpty {
            return copied
        }
        return nil
    }

    public static var isSecureInputActive: Bool {
        IsSecureEventInputEnabled()
    }

    // MARK: Pasteboard

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let snapshotTypes: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .html]

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static func snapshotPasteboard() -> PasteboardSnapshot {
        let pb = NSPasteboard.general
        var saved: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types where snapshotTypes.contains(type) {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            if !dict.isEmpty { saved.append(dict) }
        }
        return PasteboardSnapshot(items: saved)
    }

    private static func restorePasteboard(_ snapshot: PasteboardSnapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.items.isEmpty else { return }
        var newItems: [NSPasteboardItem] = []
        for dict in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            newItems.append(item)
        }
        pb.writeObjects(newItems)
    }

    // Writes the text plus the concealed marker so clipboard managers skip it.
    private static func writeTextConcealed(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(text, forType: concealedType)
        pb.writeObjects([item])
    }

    // MARK: Event synthesis

    private static func synthesizeCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // Types the text as unicode in 20-char chunks so long inserts don't overflow.
    private static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let slice = chars[i..<min(i + 20, chars.count)]
            let utf16 = Array(String(slice).utf16)

            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.005) // 5 ms between chunks
            i += 20
        }
    }
}
