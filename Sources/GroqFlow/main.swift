import AppKit
import GroqFlowKit

// Program entry runs on the main thread, i.e. the main actor's executor.
// assumeIsolated lets us build the @MainActor delegate without an async hop.
// app.run() blocks here, keeping `delegate` (a weak NSApplication reference) alive.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
