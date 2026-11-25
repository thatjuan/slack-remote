import AppKit
import Foundation

struct FilePanel {
    struct URLUnavailable: Error {}

    let tree: SlackTree
    let destination: Destination
    let requireIdle: () throws -> Void
    var requireAccount: (any UINode) throws -> Void = { _ in }

    /// The caller verified the scoped composer before handing off to the native sheet.
    func attach(_ staged: URL, deadline: Date, opening: () throws -> Void,
                openingFile: () -> Void) throws {
        var requestedSheet = false
        do {
            try Overlays.withModal(in: tree, deadline: deadline, within: nil, replacedBySheet: true,
                                   opening: opening) { modal in
                let item = try Self.uploadItem(in: modal)
                try requireContext(deadline: deadline)
                requestedSheet = true
                try? item.perform(.press)
                guard try Poll.until(deadline, {
                    try tree.refresh()
                    return Overlays.open(in: tree) == [.sheet] ? true : nil
                }) == true else { throw RemoteError.timeout }
            }
            try select(staged, deadline: deadline, openingFile: openingFile)
        } catch {
            if requestedSheet {
                try Overlays.cancelSheet(in: tree, deadline: tree.cleanupDeadline(after: 3))
            }
            throw error
        }
    }

    static func uploadItem(in modal: any UINode) throws -> any UINode {
        let menu = try modal.one(Locators.attachMenu)
        let items = menu.descendants().filter { $0.role == "AXMenuItem" }
        let candidates = items.filter { item in
            guard Locators.attachItem.matches(item), let label = try? item.one(Locators.attachItemLabel) else {
                return false
            }
            return label.descendants().contains {
                $0.role == "AXStaticText" && $0.string(.value) == "Upload from your computer"
            }
        }
        guard candidates.count == 1, let item = candidates.first, item.actionNames.contains(UIAction.press.rawValue) else {
            throw RemoteError.uiDrift(locator: "uploadMenuItem", found: candidates.count)
        }
        return item
    }

    func select(_ staged: URL, deadline: Date, openingFile: () -> Void) throws {
        let directory = staged.deletingLastPathComponent()
        let downloads = directory.deletingLastPathComponent()
        let initial = try sheet()
        let browser = try initial.one(Locators.fileBrowser)
        if try row(for: directory, in: browser) == nil, try row(for: staged, in: browser) == nil {
            let sidebar = try initial.one(Locators.fileSidebar)
            guard let row = try row(for: downloads, in: sidebar) else {
                throw URLUnavailable()
            }
            try requireContext(deadline: deadline)
            try select(row, in: sidebar)
        }
        let next = try find([directory, staged], deadline: deadline)
        if next.url == directory {
            try requireContext(deadline: deadline)
            if next.row.actionNames.contains(UIAction.open.rawValue) {
                try? next.row.perform(.open)
            } else if next.row.actionNames.contains(UIAction.press.rawValue) {
                try? next.row.perform(.press)
            } else {
                try select(next.row, in: next.browser)
            }
        }
        let target = try find([staged], deadline: deadline)
        try requireContext(deadline: deadline)
        try select(target.row, in: target.browser)
        guard try Poll.until(deadline, { try selectedOpenControl(for: staged) }) != nil else {
            throw RemoteError.timeout
        }
        try requireContext(deadline: deadline)
        try requireAccount(try SlackWindow.currentWindow(in: tree).window)
        guard let open = try selectedOpenControl(for: staged) else {
            throw RemoteError.uiDrift(locator: "selectedFileURL", found: 0)
        }
        try requireContext(deadline: deadline)
        openingFile()
        try? open.perform(.press)
        guard try Poll.until(deadline, {
            try tree.refresh()
            return try Overlays.onlySheet(in: tree) == nil ? true : nil
        }) == true else { throw RemoteError.timeout }
    }

    private func selectedOpenControl(for staged: URL) throws -> (any UINode)? {
        let sheet = try sheet()
        let browser = try sheet.one(Locators.fileBrowser)
        let selected = selectedRows(in: browser)
        guard selected.count <= 1 else {
            throw RemoteError.uiDrift(locator: "selectedFileURL", found: selected.count)
        }
        guard let row = selected.first, matches(staged, node: row) else { return nil }
        let control = try Overlays.sheetButton(.defaultButton, titled: "Open", in: sheet)
        return control.bool(.enabled) == true ? control : nil
    }

    private func requireContext(deadline: Date) throws {
        try requireIdle()
        try tree.checkInterruption()
        let client = try SlackWindow.currentWindow(in: tree)
        guard client.location.destination == destination else {
            throw RemoteError.destinationMismatch(expected: destination, actual: client.location)
        }
        guard Date() < deadline else { throw RemoteError.timeout }
    }

    private func sheet() throws -> any UINode {
        try tree.refresh()
        guard let sheet = try Overlays.onlySheet(in: tree) else {
            throw RemoteError.uiDrift(locator: Locators.fileSheet.name, found: 0)
        }
        return sheet
    }

    private func find(_ urls: [URL], deadline: Date) throws -> (url: URL, row: any UINode, browser: any UINode) {
        let match = try Poll.until(min(deadline, Date().addingTimeInterval(2))) {
            let browser = try sheet().one(Locators.fileBrowser)
            for url in urls {
                if let row = try row(for: url, in: browser) { return (url, row, browser) }
            }
            return nil
        }
        guard let match else { throw URLUnavailable() }
        return match
    }

    private func row(for url: URL, in container: any UINode) throws -> (any UINode)? {
        let rows = container.descendants().filter { isRow($0) && matches(url, node: $0) }
        guard rows.count <= 1 else { throw RemoteError.uiDrift(locator: "filePanelRowURL", found: rows.count) }
        return rows.first
    }

    private func matches(_ url: URL, node: any UINode) -> Bool {
        if let observed = node.url {
            return observed.isFileURL && observed.host == url.host && observed.path.utf8.elementsEqual(url.path.utf8)
                && observed.query == nil && observed.fragment == nil && observed.user == nil && observed.port == nil
        }
        return node.string(.filename)?.utf8.elementsEqual(url.path.utf8) == true
    }

    private func isRow(_ node: any UINode) -> Bool {
        ["AXRow", "AXCell", "AXBrowserItem"].contains(node.role)
    }

    private func select(_ row: any UINode, in container: any UINode) throws {
        if row.isSettable(.selected) {
            try? row.set(.selected, to: .bool(true))
        } else if container.isSettable(.selectedRows) {
            try? container.setNodes(.selectedRows, to: [row])
        } else if container.isSettable(.selectedChildren) {
            try? container.setNodes(.selectedChildren, to: [row])
        } else if row.bool(.selected) != true {
            throw RemoteError.uiDrift(locator: "filePanelSelectableRow", found: 0)
        }
    }

    private func selectedRows(in container: any UINode) -> [any UINode] {
        if let rows = container.nodes(.selectedRows) { return rows }
        if let children = container.nodes(.selectedChildren), children.allSatisfy(isRow) { return children }
        return container.descendants().filter { isRow($0) && $0.bool(.selected) == true }
    }
}

/// Replaces the pasteboard only while an exact staged file URL is offered to Slack's native Paste action.
enum FilePaste {
    static func withURL<T>(_ url: URL, in board: NSPasteboard = .general,
                           _ paste: (() throws -> Void) throws -> T) throws -> T {
        let originalChange = board.changeCount
        let original = try snapshot(board)
        guard board.changeCount == originalChange else {
            throw RemoteError.internalError(operation: "upload_pasteboard_changed")
        }

        let ownedChange = board.clearContents()
        let result = Result {
            guard board.changeCount == ownedChange else {
                throw RemoteError.internalError(operation: "upload_pasteboard_changed")
            }
            let wrote = board.writeObjects([url as NSURL])
            func requireOwnedURL() throws {
                guard wrote, board.pasteboardItems?.count == 1,
                      board.string(forType: .fileURL) == url.absoluteString,
                      board.changeCount == ownedChange else {
                    throw RemoteError.internalError(operation: "write_upload_pasteboard_url")
                }
            }
            try requireOwnedURL()
            return try paste(requireOwnedURL)
        }
        if board.changeCount == ownedChange {
            let cleared = board.clearContents()
            if !original.isEmpty, board.changeCount == cleared, !board.writeObjects(original) {
                throw RemoteError.internalError(operation: "restore_upload_pasteboard")
            }
        }
        return try result.get()
    }

    private static func snapshot(_ board: NSPasteboard) throws -> [NSPasteboardItem] {
        guard let items = board.pasteboardItems ?? (board.types?.isEmpty == true ? [] : nil) else {
            throw RemoteError.internalError(operation: "read_upload_pasteboard")
        }
        return try items.map { item in
            let copy = NSPasteboardItem()
            guard !item.types.isEmpty else { throw RemoteError.internalError(operation: "read_upload_pasteboard") }
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else {
                    throw RemoteError.internalError(operation: "read_upload_pasteboard")
                }
            }
            return copy
        }
    }
}
