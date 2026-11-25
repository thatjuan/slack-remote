import Foundation

struct FilePanel {
    let tree: SlackTree
    let destination: Destination
    let requireIdle: () throws -> Void

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
        guard items.count == 4, items.allSatisfy(Locators.attachItem.matches),
              let first = items.first?.domID?.wholeMatch(of: #/menu-([0-9]+)-0/#),
              items.enumerated().allSatisfy({ $0.element.domID == "menu-\(first.output.1)-\($0.offset)" }),
              let item = items.last, item.actionNames.contains(UIAction.press.rawValue) else {
            throw RemoteError.uiDrift(locator: "uploadMenuItem", found: items.count)
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
                throw RemoteError.uiDrift(locator: "downloadsRowURL", found: 0)
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
        let open: (any UINode)? = try Poll.until(deadline) {
            let sheet = try sheet()
            let browser = try sheet.one(Locators.fileBrowser)
            let selected = selectedRows(in: browser)
            guard selected.count <= 1 else {
                throw RemoteError.uiDrift(locator: "selectedFileURL", found: selected.count)
            }
            guard selected.count == 1, selected.first.map({ matches(staged, node: $0) }) == true else { return nil }
            guard let control = sheet.node(.defaultButton), control.role == "AXButton" else {
                throw RemoteError.uiDrift(locator: "filePanelOpen", found: 0)
            }
            return control.bool(.enabled) == true ? control : nil
        }
        guard let open else { throw RemoteError.timeout }
        try requireContext(deadline: deadline)
        openingFile()
        try? open.perform(.press)
        guard try Poll.until(deadline, {
            try tree.refresh()
            return try Overlays.onlySheet(in: tree) == nil ? true : nil
        }) == true else { throw RemoteError.timeout }
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
        let match = try Poll.until(deadline) {
            let browser = try sheet().one(Locators.fileBrowser)
            for url in urls {
                if let row = try row(for: url, in: browser) { return (url, row, browser) }
            }
            return nil
        }
        guard let match else { throw RemoteError.uiDrift(locator: "filePanelRowURL", found: 0) }
        return match
    }

    private func row(for url: URL, in container: any UINode) throws -> (any UINode)? {
        let rows = container.descendants().filter { isRow($0) && matches(url, node: $0) }
        guard rows.count <= 1 else { throw RemoteError.uiDrift(locator: "filePanelRowURL", found: rows.count) }
        return rows.first
    }

    private func matches(_ url: URL, node: any UINode) -> Bool {
        if let observed = node.url {
            return observed.isFileURL && observed.host == url.host && observed.path == url.path
                && observed.query == nil && observed.fragment == nil
        }
        return node.string(.filename) == url.path
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
