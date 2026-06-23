import SwiftUI

@main
struct AIMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The UI (status bar item, popover, window) is driven entirely by
        // AppDelegate. A Settings scene keeps SwiftUI happy without creating
        // an extra auto-managed window.
        Settings {
            EmptyView()
        }
    }
}
