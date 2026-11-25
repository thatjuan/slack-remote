import SlackRemoteCore

final class FakeNode: UINode {
    var role: String
    var subrole: String?
    var domClasses: [String]
    var domID: String?
    var children: [any UINode]
    var attributes: [UIAttribute: UIValue]
    var actionNames: [String] = []
    var settableAttributes: Set<UIAttribute> = []
    var onSet: ((UIAttribute, UIValue) throws -> Void)?
    var onPerform: ((UIAction) throws -> Void)?

    private(set) var setCalls: [(attribute: UIAttribute, value: UIValue)] = []
    private(set) var performCalls: [UIAction] = []
    private(set) var readCalls: [UIAttribute] = []

    init(role: String, subrole: String? = nil, domClasses: [String] = [], domID: String? = nil,
         children: [any UINode] = [], attributes: [UIAttribute: UIValue] = [:]) {
        self.role = role
        self.subrole = subrole
        self.domClasses = domClasses
        self.domID = domID
        self.children = children
        self.attributes = attributes
    }

    func string(_ attribute: UIAttribute) -> String? {
        readCalls.append(attribute)
        guard case .string(let text) = attributes[attribute] else { return nil }
        return text
    }

    func bool(_ attribute: UIAttribute) -> Bool? {
        readCalls.append(attribute)
        guard case .bool(let flag) = attributes[attribute] else { return nil }
        return flag
    }

    func isSettable(_ attribute: UIAttribute) -> Bool {
        settableAttributes.contains(attribute)
    }

    func set(_ attribute: UIAttribute, to value: UIValue) throws {
        setCalls.append((attribute, value))
        if let onSet {
            try onSet(attribute, value)
        } else {
            attributes[attribute] = value
        }
    }

    func perform(_ action: UIAction) throws {
        performCalls.append(action)
        try onPerform?(action)
    }
}
