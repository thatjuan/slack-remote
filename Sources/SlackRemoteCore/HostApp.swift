import AppKit
import Darwin

/// The likely Accessibility host, inferred from ancestors because TCC's responsible process is not public API.
public struct HostApp: Equatable, Sendable {
    public let name: String
    public let bundleID: String?
    public let path: String

    /// Find the closest ancestor app, using its outermost bundle for nested helpers.
    public static func current() -> HostApp? {
        guard let path = bundlePath(startingAt: getppid(), parent: parentPID, executablePath: executablePath) else {
            return nil
        }
        let bundle = Bundle(path: path)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return HostApp(name: name, bundleID: bundle?.bundleIdentifier, path: path)
    }

    static func bundlePath(startingAt pid: pid_t, parent: (pid_t) -> pid_t?,
                           executablePath: (pid_t) -> String?) -> String? {
        var current = pid
        var visited: Set<pid_t> = []
        for _ in 0..<64 {
            guard current > 1, visited.insert(current).inserted else { return nil }
            if let executable = executablePath(current), let bundle = outermostBundle(in: executable) {
                return bundle
            }
            guard let next = parent(current) else { return nil }
            current = next
        }
        return nil
    }

    static func outermostBundle(in executablePath: String) -> String? {
        let components = (executablePath as NSString).pathComponents
        guard let index = components.dropLast().firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return NSString.path(withComponents: Array(components[...index]))
    }

    private static func parentPID(_ pid: pid_t) -> pid_t? {
        var query = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&query, UInt32(query.count), &info, &size, nil, 0) == 0,
              size == MemoryLayout<kinfo_proc>.size else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN, a macro Swift cannot import.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
