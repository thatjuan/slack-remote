import AppKit
import SlackRemoteCore

if let server = try? HelperServer() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let statusMenu = StatusMenu(server: server)
    withExtendedLifetime(statusMenu) { app.run() }
}
