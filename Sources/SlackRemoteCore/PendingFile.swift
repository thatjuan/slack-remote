struct PendingFile {
    let node: any UINode

    static func all(in scope: any UINode) -> [PendingFile] {
        scope.all(Locators.pendingFile).map { PendingFile(node: $0) }
    }

    func name() throws -> String {
        let label = try node.one(Locators.pendingFileName)
        guard let value = label.string(.value), !value.isEmpty else {
            throw RemoteError.uiDrift(locator: Locators.pendingFileName.name, found: 0)
        }
        return value
    }

    static func require(_ name: String, in files: [PendingFile]) throws {
        guard files.count == 1, let file = files.first, let observed = try? file.name(),
              observed.utf8.elementsEqual(name.utf8) else {
            throw RemoteError.writeUnverified(draftLeft: false)
        }
    }

    func remove() throws {
        try node.one(Locators.removePendingFile).perform(.press)
    }
}
