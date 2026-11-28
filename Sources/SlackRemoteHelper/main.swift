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
        installMainMenu()
        let pool = (try? AccountStore.load()).map { SessionPool(file: $0) }
        let engine = Engine(pool: pool)
        if let server = try? HelperServer(callHandler: { call, file, _ in await engine.perform(call, file: file) }) {
            let statusMenu = StatusMenu(server: server, pool: pool, engine: engine)
            engine.useMenu(statusMenu)
            withExtendedLifetime(statusMenu) { app.run() }
        }
    }
}
