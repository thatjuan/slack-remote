import Foundation

public enum UIAttribute: String {
    case title = "AXTitle"
    case description = "AXDescription"
    case value = "AXValue"
    case url = "AXURL"
    case filename = "AXFilename"
    case selected = "AXSelected"
    case selectedRows = "AXSelectedRows"
    case selectedChildren = "AXSelectedChildren"
    case cancelButton = "AXCancelButton"
    case defaultButton = "AXDefaultButton"
    case enabled = "AXEnabled"
    case focused = "AXFocused"
    case main = "AXMain"
    case modal = "AXModal"
    case minimized = "AXMinimized"
    case selectedText = "AXSelectedText"
    case selectedTextRange = "AXSelectedTextRange"
}

public enum UIAction: String {
    case press = "AXPress"
    case scrollToVisible = "AXScrollToVisible"
    case showMenu = "AXShowMenu"
    case open = "AXOpen"
}

public enum UIValue: Equatable {
    case string(String)
    case bool(Bool)
    case range(location: Int, length: Int)
}

public protocol UINode {
    var role: String { get }
    var subrole: String? { get }
    var domClasses: [String] { get }
    var domID: String? { get }
    var children: [any UINode] { get }
    var actionNames: [String] { get }
    func isSettable(_ attribute: UIAttribute) -> Bool
    func string(_ attribute: UIAttribute) -> String?
    func bool(_ attribute: UIAttribute) -> Bool?
    func node(_ attribute: UIAttribute) -> (any UINode)?
    func nodes(_ attribute: UIAttribute) -> [any UINode]?
    func setNodes(_ attribute: UIAttribute, to nodes: [any UINode]) throws
    func set(_ attribute: UIAttribute, to value: UIValue) throws
    func perform(_ action: UIAction) throws
}

public extension UINode {
    var url: URL? { string(.url).flatMap(URL.init(string:)) }

    func node(_ attribute: UIAttribute) -> (any UINode)? { nil }
    func nodes(_ attribute: UIAttribute) -> [any UINode]? { nil }
    func setNodes(_ attribute: UIAttribute, to nodes: [any UINode]) throws {
        throw RemoteError.uiDrift(locator: attribute.rawValue, found: 0)
    }

    /// Depth-first, document order, excluding self.
    func descendants() -> [any UINode] {
        var result: [any UINode] = []
        var pending = Array(children.reversed())
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }

    func all(_ locator: Locator) -> [any UINode] {
        descendants().filter(locator.matches)
    }

    /// Returns the only match or reports the locator and its match count.
    func one(_ locator: Locator) throws -> any UINode {
        let matches = all(locator)
        guard matches.count == 1, let node = matches.first else {
            throw RemoteError.uiDrift(locator: locator.name, found: matches.count)
        }
        return node
    }
}
