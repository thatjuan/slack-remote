struct PendingFile {
    let node: any UINode

    static func all(in scope: any UINode) -> [PendingFile] {
        scope.all(Locators.pendingFile).map { PendingFile(node: $0) }
    }

    func name() throws -> String {
        let title = node.string(.title)
        guard let title, !title.isEmpty,
              node.string(.description)?.utf8.elementsEqual(title.utf8) != false else {
            throw RemoteError.uiDrift(locator: "pendingFileName", found: 0)
        }
        return title
    }

    @discardableResult
    static func require(_ name: String, in files: [PendingFile]) throws -> PendingFile {
        guard files.count == 1, let file = files.first, let observed = try? file.name(),
              observed.utf8.elementsEqual(name.utf8) else {
            throw RemoteError.writeUnverified(draftLeft: false)
        }
        return file
    }

    func removeControl() -> (any UINode)? {
        guard let button = try? node.one(Locators.removePendingFile),
              button.actionNames.contains(UIAction.press.rawValue) else { return nil }
        return button
    }
}
