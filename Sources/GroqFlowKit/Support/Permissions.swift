import Foundation
import AVFoundation
import ApplicationServices
import CoreGraphics
import AppKit

public enum PermissionPane {
    case microphone
    case inputMonitoring
    case accessibility
}

// Check / request / deep-link the three TCC permissions GroqFlow needs.
public enum Permissions {
    // MARK: - Status

    public static var micGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Requests

    public static func requestMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func requestInputMonitoring() {
        // Triggers the system Input Monitoring prompt if not yet decided.
        _ = CGRequestListenEventAccess()
    }

    public static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt;
        // using the literal avoids the Unmanaged/CFString import ambiguity.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Settings deep links

    public static func openSettingsPane(_ pane: PermissionPane) {
        let anchor: String
        switch pane {
        case .microphone:
            anchor = "Privacy_Microphone"
        case .inputMonitoring:
            anchor = "Privacy_ListenEvent"
        case .accessibility:
            anchor = "Privacy_Accessibility"
        }
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
