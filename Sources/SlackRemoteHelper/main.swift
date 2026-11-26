import AppKit
import ServiceManagement
import SlackRemoteCore
import SlackRemoteWeb

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
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let webKitPoC = WebKitPoC()
        if let server = try? HelperServer(inProcess: { request in await webKitPoC.handle(request) }) {
            webKitPoC.restoreAccounts()
            let statusMenu = StatusMenu(server: server, webKitPoC: webKitPoC)
            withExtendedLifetime(statusMenu) { app.run() }
        }
    }
}
