import AppKit
import ApplicationServices
import Darwin
import Foundation

public final class SlackApp {
    public static let bundleIdentifier = "com.tinyspeck.slackmacgap"
    public static let testedVersionPrefixes = ["4.53."]

    public let version: String
    private var commandWarnings: [String] = []
    public var warnings: [String] {
        let versionWarnings = Self.testedVersionPrefixes.contains(where: version.hasPrefix) ? [] : ["untested_slack_version"]
        return versionWarnings + commandWarnings
    }

    public func warn(_ code: String) {
        if !commandWarnings.contains(code) { commandWarnings.append(code) }
    }

    private let identity: ProcessIdentity
    private let supportDirectory: URL
    private let readWindows: () -> [any UINode]
    private let setMode: (Bool) throws -> Void
    private let checkAvailable: () throws -> Void
    private let prepareTree: () throws -> Void
    private let runningApplication: NSRunningApplication?

    public static func requireRunning() throws -> NSRunningApplication {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard applications.count <= 1 else { throw RemoteError.ambiguousSlack }
        guard let app = applications.first, app.isFinishedLaunching, !app.isTerminated else {
            throw RemoteError.slackNotRunning
        }
        return app
    }

    public static func requireVisible(_ app: NSRunningApplication) throws {
        guard !app.isHidden else { throw RemoteError.slackWindowUnavailable }
    }

    public convenience init(running app: NSRunningApplication) throws {
        guard let identity = ProcessIdentity(app) else { throw RemoteError.slackNotRunning }
        let version = app.bundleURL.flatMap { Bundle(url: $0) }?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let element = AXUIElementCreateApplication(identity.pid)
        self.init(identity: identity, version: version, supportDirectory: CommandLock.supportDirectory,
                  runningApplication: app, readWindows: {
            guard identity.currentApplication() != nil else { return [] }
            var windows: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success else {
                return []
            }
            return (windows as? [AXUIElement] ?? []).map(AXNode.init)
        }, setMode: { enabled in
            guard identity.currentApplication() != nil else { throw RemoteError.slackNotRunning }
            let result = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString,
                                                      enabled ? kCFBooleanTrue : kCFBooleanFalse)
            guard result == .success else {
                throw RemoteError.axFailure(operation: "AXManualAccessibility", code: result.rawValue)
            }
        }, checkAvailable: {
            let running = try SlackApp.requireRunning()
            guard identity.matches(running) else { throw RemoteError.slackNotRunning }
            try SlackApp.requireVisible(running)
        }, prepareTree: {
            let timeout = AXUIElementSetMessagingTimeout(element, 2)
            guard timeout == .success else {
                throw RemoteError.axFailure(operation: "AXUIElementSetMessagingTimeout", code: timeout.rawValue)
            }
        })
    }

    init(identity: ProcessIdentity, version: String = "4.53.0", supportDirectory: URL,
         runningApplication: NSRunningApplication? = nil, readWindows: @escaping () -> [any UINode],
         setMode: @escaping (Bool) throws -> Void, checkAvailable: @escaping () throws -> Void = {},
         prepareTree: @escaping () throws -> Void = {}) {
        self.identity = identity
        self.version = version
        self.supportDirectory = supportDirectory
        self.runningApplication = runningApplication
        self.readWindows = readWindows
        self.setMode = setMode
        self.checkAvailable = checkAvailable
        self.prepareTree = prepareTree
    }

    func bundleURLForNavigation() throws -> URL {
        try checkAvailable()
        guard let url = runningApplication?.bundleURL else {
            throw RemoteError.internalError(operation: "locate_slack_bundle")
        }
        return url
    }

    /// Runs body with fresh window roots and restores the mode it owns on every exit path.
    public func withTree<T>(deadline: Date, _ body: (SlackTree) throws -> T) throws -> T {
        try checkAvailable()
        try prepareTree()
        let start = Date()
        let (marker, recovered) = try recoveryMarker()
        var needsRestore = recovered

        func restore() throws {
            guard needsRestore else { return }
            try setMode(false)
            try removeMarker(marker)
            needsRestore = false
        }

        var sessionTree: SlackTree?
        let sources = [SIGINT, SIGTERM, SIGHUP].map { number in
            let previous = signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                if sessionTree?.requestInterruption() == true { return }
                try? restore()
                exit(130)
            }
            source.resume()
            return (number, previous, source)
        }
        defer {
            for (number, previous, source) in sources {
                source.cancel()
                signal(number, previous)
            }
        }

        let result = Result {
            guard Date() < deadline else { throw RemoteError.treeUnavailable }
            let tree = SlackTree(refresh: readWindows)
            sessionTree = tree
            let treeWasPresent = tree.shape() != nil
            if !treeWasPresent {
                try saveMarker(marker)
                needsRestore = true
                try setMode(true)
            }

            let counts = try tree.settle(until: deadline)

            tree.sessionInfo = .init(mode: recovered ? .recovered : (treeWasPresent ? .alreadyPresent : .enabled),
                                     elapsed: Date().timeIntervalSince(start), nodeCount: counts.reduce(0, +))
            if needsRestore {
                // Keep the recovery marker across both writes. We only rebuild a mode this session owns.
                tree.rebuildOwnedMode = { [weak tree] deadline in
                    guard let tree, Date() < deadline else { throw RemoteError.timeout }
                    try self.setMode(false)
                    Poll.wait(until: deadline)
                    guard Date() < deadline else { throw RemoteError.timeout }
                    try self.setMode(true)
                    _ = try tree.settle(until: deadline)
                }
            }
            defer { tree.rebuildOwnedMode = nil }
            return try body(tree)
        }
        try restore()
        let value = try result.get()
        try sessionTree?.checkInterruption()
        return value
    }

    private func recoveryMarker() throws -> (URL, Bool) {
        let prefix = "ax-enabled-"
        let marker = supportDirectory.appendingPathComponent("\(prefix)\(identity.pid)")
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: supportDirectory,
                                                                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw RemoteError.internalError(operation: "list_tree_recovery_markers")
        }
        var owned = false
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            guard let pid = Int32(file.lastPathComponent.dropFirst(prefix.count)) else { continue }
            let kind = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if kind?.isDirectory == true { continue }
            if pid != identity.pid || file.lastPathComponent != marker.lastPathComponent || kind?.isSymbolicLink == true {
                try removeMarker(file)
                continue
            }
            let data: Data
            do {
                data = try Data(contentsOf: marker)
            } catch {
                throw RemoteError.internalError(operation: "read_tree_recovery_marker")
            }
            let savedIdentity = try? JSONDecoder().decode(ProcessIdentity.self, from: data)
            owned = savedIdentity == identity
            if !owned { try removeMarker(marker) }
        }
        return (marker, owned)
    }

    private func saveMarker(_ marker: URL) throws {
        do {
            try JSONEncoder().encode(identity).write(to: marker, options: .atomic)
        } catch {
            throw RemoteError.internalError(operation: "save_tree_recovery_marker")
        }
    }

    private func removeMarker(_ marker: URL) throws {
        if unlink(marker.path) != 0, errno != ENOENT {
            throw RemoteError.internalError(operation: "remove_tree_recovery_marker")
        }
    }
}

struct ProcessIdentity: Codable, Equatable {
    let pid: pid_t
    let launchDate: Date

    init(pid: pid_t, launchDate: Date) {
        self.pid = pid
        self.launchDate = launchDate
    }

    init?(_ app: NSRunningApplication) {
        guard app.processIdentifier > 0, let launchDate = app.launchDate, !app.isTerminated else { return nil }
        self.init(pid: app.processIdentifier, launchDate: launchDate)
    }

    func matches(_ app: NSRunningApplication) -> Bool {
        ProcessIdentity(app) == self
    }

    func currentApplication() -> NSRunningApplication? {
        guard let application = NSRunningApplication(processIdentifier: pid), matches(application) else { return nil }
        return application
    }
}

public final class SlackTree {
    struct Interruption: Error {}

    public struct SessionInfo {
        public enum Mode: String {
            case enabled = "enabled by this run"
            case alreadyPresent = "already available"
            case recovered = "recovered previous ownership"
        }

        public let mode: Mode
        public let elapsed: TimeInterval
        public let nodeCount: Int
    }

    public private(set) var windows: [any UINode]
    public internal(set) var sessionInfo: SessionInfo?
    var rebuildOwnedMode: ((Date) throws -> Void)?
    private let readWindows: (() -> [any UINode])?
    var unwindOnSignal = false
    private var interruptionDeadline: Date?
    private var cleaningUp = false
    public var interruptionRequested: Bool { interruptionDeadline != nil }

    public init(windows: [any UINode]) {
        self.windows = windows
        readWindows = nil
    }

    public init(refresh readWindows: @escaping () -> [any UINode]) {
        self.readWindows = readWindows
        windows = readWindows()
    }

    func reload() {
        if let readWindows { windows = readWindows() }
    }

    public func refresh() throws {
        try checkInterruption()
        reload()
        try checkInterruption()
        guard !SlackWindow.clientWindows(in: self).isEmpty else { throw RemoteError.treeUnavailable }
    }

    // The main-queue signal handler only records cancellation. The caller unwinds its own UI transaction.
    func requestInterruption() -> Bool {
        guard unwindOnSignal else { return false }
        if interruptionDeadline == nil { interruptionDeadline = Date().addingTimeInterval(5) }
        return true
    }

    func checkInterruption() throws {
        if interruptionRequested && !cleaningUp { throw Interruption() }
    }

    func cleanupDeadline(after seconds: TimeInterval) -> Date {
        min(Date().addingTimeInterval(seconds), interruptionDeadline ?? .distantFuture)
    }

    func withCleanup<T>(_ work: () throws -> T) rethrows -> T {
        let previous = cleaningUp
        cleaningUp = true
        defer { cleaningUp = previous }
        return try work()
    }

    func settle(until deadline: Date) throws -> [Int] {
        var previousShape: [Int]?
        guard let counts = Poll.until(deadline, {
            reload()
            let shape = shape()
            defer { previousShape = shape }
            return shape == previousShape ? shape : nil
        }) else { throw RemoteError.treeUnavailable }
        return counts
    }

    func shape() -> [Int]? {
        var containsWebArea = false
        let counts = windows.map { window in
            let nodes = window.descendants()
            if nodes.contains(where: {
                Locators.webArea.matches($0) && ($0.string(.url).map(ClientLocation.parse) ?? .notClient) != .notClient
            }) { containsWebArea = true }
            return nodes.count + 1
        }
        return containsWebArea ? counts : nil
    }
}
