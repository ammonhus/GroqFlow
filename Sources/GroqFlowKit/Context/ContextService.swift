import AppKit
import ApplicationServices

// Reads the frontmost app and (when Accessibility is granted) the text
// preceding the caret, so formatting can match the destination app's style
// and capitalization.
@MainActor
public enum ContextService {

    public static func snapshot(axEnabled: Bool) -> AppContext {
        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier
        let appName = front?.localizedName
        let preceding = axEnabled ? readPrecedingText() : nil
        return AppContext(bundleID: bundleID,
                          appName: appName,
                          precedingText: preceding,
                          category: category(forBundleID: bundleID))
    }

    public static func category(forBundleID bundleID: String?) -> StyleCategory {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return .other }
        if hasAnyPrefix(id, personalMessagingIDs) { return .personalMessaging }
        if hasAnyPrefix(id, workMessagingIDs) { return .workMessaging }
        if hasAnyPrefix(id, emailIDs) { return .email }
        if hasAnyPrefix(id, codeIDs) { return .code }
        return .other
    }

    // MARK: Bundle-id maps (lowercased prefixes)

    private static let personalMessagingIDs = [
        "com.apple.mobilesms",              // Messages / iMessage
        "com.apple.ichat",
        "net.whatsapp.whatsapp",
        "whatsapp.whatsapp",
        "desktop.whatsapp",
        "ph.telegra.desktop",
        "org.telegram",
        "com.tdesktop.telegram",
        "ru.keepcoder.telegram",            // native macOS Telegram
        "org.whispersystems.signal-desktop",
        "org.whispersystems.signal",
    ]

    private static let workMessagingIDs = [
        "com.tinyspeck.slackmacgap",        // Slack
        "com.microsoft.teams",              // covers teams and teams2
        "com.hnc.discord",
        "com.discordapp.discord",
    ]

    private static let emailIDs = [
        "com.apple.mail",
        "com.microsoft.outlook",
        "com.superhuman",
        "com.missiveapp",
    ]

    private static let codeIDs = [
        "com.apple.dt.xcode",
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.microsoft.vscode",             // covers VS Code + Insiders
        "com.visualstudio.code.oss",
        "com.vscodium",
        "com.todesktop.230313mzl4w4u92",    // Cursor
        "com.exafunction.windsurf",
        "com.codeium.windsurf",
        "dev.warp",                         // Warp: dev.warp.Warp-Stable
    ]

    private static func hasAnyPrefix(_ id: String, _ prefixes: [String]) -> Bool {
        for prefix in prefixes where id.hasPrefix(prefix) { return true }
        return false
    }

    // MARK: Accessibility read

    // Best-effort read of the text before the caret in the focused element.
    private static func readPrecedingText() -> String? {
        let system = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String else { return nil }

        // Prefer everything before the caret when we can resolve its position.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef {
            var cfRange = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) {
                let ns = value as NSString
                if cfRange.location >= 0 && cfRange.location <= ns.length {
                    return truncatePreceding(ns.substring(to: cfRange.location))
                }
            }
        }

        return truncatePreceding(value)
    }

    // Keeps the last 300 characters; nil for empty/missing text.
    static func truncatePreceding(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if text.count <= 300 { return text }
        return String(text.suffix(300))
    }
}
