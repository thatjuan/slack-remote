import Darwin
import Foundation
import SlackRemoteCore

/// Streams an open descriptor to Slack's external upload endpoint.
public enum FileUploader {
    public static func post(to url: URL, file: FileHandle, size: Int64, deadline: Date,
                            sessionCookies: @Sendable (URL) async throws -> [HTTPCookie]) async throws {
        guard slackHTTPSURL(url.absoluteString) != nil else {
            throw RemoteError.slackAPI(method: "files.getUploadURLExternal", error: "invalid_upload_url")
        }
        let descriptorURL = URL(fileURLWithPath: "/dev/fd/\(file.fileDescriptor)")
        var body = descriptorURL
        var temporary: URL?
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }

        if needsStaging(file) {
            body = try stage(file, size: size, deadline: deadline)
            temporary = body
        }
        var status: Int
        do {
            status = try await post(to: url, body: body, size: size, deadline: deadline)
        } catch let error as URLError where [.fileDoesNotExist, .noPermissionsToReadFile, .cannotOpenFile].contains(error.code) {
            guard temporary == nil else { throw RemoteError.fileRejected(reason: "unreadable") }
            body = try stage(file, size: size, deadline: deadline)
            temporary = body
            status = try await postBytes(to: url, body: body, size: size, deadline: deadline)
        } catch is URLError {
            try Task.checkCancellation()
            throw RemoteError.uploadUnconfirmed
        }

        if status == 401 || status == 403 {
            let cookies = try await sessionCookies(url)
            if !cookies.isEmpty {
                status = try await postBytes(to: url, body: body, size: size, deadline: deadline, cookies: cookies)
            }
        }

        switch status {
        case 200..<300: return
        case 400..<500: throw RemoteError.slackAPI(method: "upload", error: "http_\(status)")
        default: throw RemoteError.uploadUnconfirmed
        }
    }

    /// URLSession can reopen the source behind /dev/fd. A mounted volume can
    /// require separate macOS file access even though the passed descriptor is readable.
    private static func needsStaging(_ file: FileHandle) -> Bool {
        var source = statfs()
        var local = statfs()
        guard fstatfs(file.fileDescriptor, &source) == 0,
              statfs(FileManager.default.temporaryDirectory.path, &local) == 0 else {
            return false
        }
        return source.f_fsid.val != local.f_fsid.val
    }

    /// Maps errors from the upload request after a readable body has been selected.
    private static func postBytes(to url: URL, body: URL, size: Int64, deadline: Date,
                                  cookies: [HTTPCookie] = []) async throws -> Int {
        do { return try await post(to: url, body: body, size: size, deadline: deadline, cookies: cookies) }
        catch is URLError {
            try Task.checkCancellation()
            throw RemoteError.uploadUnconfirmed
        }
    }

    /// Sends bytes to Slack without following redirects or accepting server cookies.
    private static func post(to url: URL, body: URL, size: Int64, deadline: Date,
                             cookies: [HTTPCookie] = []) async throws -> Int {
        try Task.checkCancellation()
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw RemoteError.timeout }
        var request = URLRequest(url: url, timeoutInterval: remaining)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        request.setValue(SafariUserAgent.current, forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = remaining
        configuration.timeoutIntervalForResource = remaining
        let network = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { network.finishTasksAndInvalidate() }
        let (_, response) = try await network.upload(for: request, fromFile: body)
        guard let http = response as? HTTPURLResponse else { throw RemoteError.uploadUnconfirmed }
        return http.statusCode
    }

    /// Copies at most the checked file length into a private file when URLSession requires a regular path.
    private static func stage(_ file: FileHandle, size: Int64, deadline: Date) throws -> URL {
        let template = FileManager.default.temporaryDirectory.appendingPathComponent("slack-remote-upload.XXXXXX")
        var path = Array(template.path.utf8CString)
        let descriptor = mkstemp(&path)
        guard descriptor >= 0 else { throw RemoteError.fileRejected(reason: "unreadable") }
        let url = URL(fileURLWithPath: String(cString: path))
        let staged = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            var offset: Int64 = 0
            while offset < size {
                try Task.checkCancellation()
                guard Date() < deadline else { throw RemoteError.timeout }
                let count = min(buffer.count, Int(size - offset))
                let read = buffer.withUnsafeMutableBytes { pread(file.fileDescriptor, $0.baseAddress, count, offset) }
                if read < 0, errno == EINTR { continue }
                guard read > 0 else { throw RemoteError.fileRejected(reason: "unreadable") }
                try staged.write(contentsOf: buffer.prefix(read))
                offset += Int64(read)
            }
            try staged.close()
            return url
        } catch {
            try? staged.close()
            try? FileManager.default.removeItem(at: url)
            if error is RemoteError || error is CancellationError { throw error }
            throw RemoteError.fileRejected(reason: "unreadable")
        }
    }
}
