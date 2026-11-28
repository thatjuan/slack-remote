import AppKit
import ServiceManagement
import SlackRemoteCore
import SlackRemoteWeb

MainActor.assumeIsolated {
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
    } else {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let webKit = WebKitPoC()
        if let server = try? HelperServer(inProcess: { await webKit.handle($0) }) {
            webKit.start()
            let statusMenu = StatusMenu(server: server, webKit: webKit)
            withExtendedLifetime(statusMenu) { app.run() }
        }
    }
}
