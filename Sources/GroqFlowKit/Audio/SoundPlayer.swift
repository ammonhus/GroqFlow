import AppKit

// Subtle system pings for dictation lifecycle events.
@MainActor
public enum SoundPlayer {
    public static var enabled: Bool = true

    public static func playStart() { play("Pop") }
    public static func playStop() { play("Tink") }
    public static func playCancel() { play("Bottle") }
    public static func playError() { play("Basso") }

    private static func play(_ name: NSSound.Name) {
        guard enabled else { return }
        NSSound(named: name)?.play()
    }
}
