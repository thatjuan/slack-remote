import Foundation

public enum HelperForwarding {
    public static func shouldForward(arguments: [String], noHelper: String?) -> Bool {
        guard noHelper != "1", let command = arguments.first else { return false }
        return !["help", "--help", "-h", "--version"].contains(command)
    }

    public struct Upload: Equatable {
        public let path: String
        public let arguments: [String]
    }

    public static let uploadDescriptor: Int32 = 3

    public static func rewriteUpload(arguments: [String]) -> Upload? {
        guard arguments.first == "upload" else { return nil }
        var file: (range: Range<Int>, path: String)?
        var index = 1
        while index < arguments.count, arguments[index] != "--" {
            let argument = arguments[index]
            if argument == "--file", index + 1 < arguments.count {
                let path = arguments[index + 1]
                if path == "-" || !path.hasPrefix("-") {
                    file = (index..<(index + 2), path)
                    index += 2
                    continue
                }
            }
            if argument.hasPrefix("--file=") {
                file = (index..<(index + 1), String(argument.dropFirst("--file=".count)))
            }
            index += 1
        }
        guard let file else { return nil }
        let requested = URL(fileURLWithPath: NSString(string: file.path).expandingTildeInPath)
        let name = requested.lastPathComponent
        let nameOption = name.hasPrefix("-") ? ["--file-name=\(name)"] : ["--file-name", name]
        var rewritten = arguments
        rewritten.replaceSubrange(file.range, with: ["--file", "/dev/fd/\(uploadDescriptor)"] + nameOption)
        return Upload(path: file.path, arguments: rewritten)
    }
}
