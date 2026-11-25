import AppKit
import ServiceManagement
import SlackRemoteCore

if CommandLine.arguments.dropFirst() == ["--unregister"] {
    let login = SMAppService.mainApp
    do {
        if login.status == .enabled || login.status == .requiresApproval {
            try login.unregister()
        }
        UserDefaults.standard.removeObject(forKey: StatusMenu.hasLaunchedKey)
    } catch {
        NSLog("SlackRemote could not unregister Open at Login: %@", error.localizedDescription)
        exit(EXIT_FAILURE)
    }
} else if let server = try? HelperServer() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let statusMenu = StatusMenu(server: server)
    withExtendedLifetime(statusMenu) { app.run() }
}
