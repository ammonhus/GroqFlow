import Foundation
import ServiceManagement

// Launch-at-login toggle backed by SMAppService (macOS 13+).
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            Log.app.error("LaunchAtLogin update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
