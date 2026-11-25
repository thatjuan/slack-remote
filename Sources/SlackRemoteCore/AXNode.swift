import ApplicationServices
import Foundation

/// The element's structure is snapshotted once. Other attributes are read on demand.
public final class AXNode: UINode {
    public let role: String
    public let subrole: String?
    public let domClasses: [String]
    public let domID: String?

    private let element: AXUIElement
    private let childElements: [AXUIElement]
    public private(set) lazy var children: [any UINode] = childElements.map(AXNode.init)

    public var actionNames: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    public func isSettable(_ attribute: UIAttribute) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute.rawValue as CFString, &settable) == .success
            && settable.boolValue
    }

    public init(_ element: AXUIElement) {
        self.element = element
        let names = [kAXRoleAttribute, kAXSubroleAttribute, "AXDOMClassList", "AXDOMIdentifier", kAXChildrenAttribute]
        var response: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &response)
        let values = response as? [AnyObject] ?? []
        let attributes = result == .success && values.count == names.count
            ? values.map(Self.presentValue)
            : Array(repeating: nil, count: names.count)

        role = attributes[0] as? String ?? ""
        subrole = attributes[1] as? String
        domClasses = attributes[2] as? [String] ?? []
        domID = attributes[3] as? String
        childElements = attributes[4] as? [AXUIElement] ?? []
    }

    public func string(_ attribute: UIAttribute) -> String? {
        let value = read(attribute)
        if attribute == .url { return (value as? URL)?.absoluteString ?? value as? String }
        return value as? String
    }

    public func bool(_ attribute: UIAttribute) -> Bool? {
        guard let value = read(attribute) else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return value as? Bool }
        // Accessibility represents checkboxes as integer states in some clients.
        guard attribute == .value, role == "AXCheckBox", let number = value as? NSNumber else { return nil }
        switch number.doubleValue {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    public func set(_ attribute: UIAttribute, to value: UIValue) throws {
        let encoded: CFTypeRef
        switch (attribute, value) {
        case (.value, .string(let text)), (.selectedText, .string(let text)):
            encoded = text as CFString
        case (.value, .bool(let flag)), (.focused, .bool(let flag)), (.selected, .bool(let flag)):
            encoded = flag ? kCFBooleanTrue : kCFBooleanFalse
        case (.selectedTextRange, .range(let location, let length)):
            var range = CFRange(location: location, length: length)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else {
                throw RemoteError.axFailure(operation: attribute.rawValue, code: AXError.illegalArgument.rawValue)
            }
            encoded = rangeValue
        default:
            throw RemoteError.axFailure(operation: attribute.rawValue, code: AXError.illegalArgument.rawValue)
        }
        try setAttribute(attribute, encoded)
    }

    public func node(_ attribute: UIAttribute) -> (any UINode)? {
        guard let value = read(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXNode(unsafeDowncast(value, to: AXUIElement.self))
    }

    public func nodes(_ attribute: UIAttribute) -> [any UINode]? {
        (read(attribute) as? [AXUIElement])?.map(AXNode.init)
    }

    public func setNodes(_ attribute: UIAttribute, to nodes: [any UINode]) throws {
        let elements = nodes.compactMap { ($0 as? AXNode)?.element }
        guard elements.count == nodes.count else {
            throw RemoteError.axFailure(operation: attribute.rawValue, code: AXError.illegalArgument.rawValue)
        }
        try setAttribute(attribute, elements as CFArray)
    }

    private func setAttribute(_ attribute: UIAttribute, _ value: CFTypeRef) throws {
        let result = AXUIElementSetAttributeValue(element, attribute.rawValue as CFString, value)
        guard result == .success else {
            throw RemoteError.axFailure(operation: attribute.rawValue, code: result.rawValue)
        }
    }

    public func perform(_ action: UIAction) throws {
        let result = AXUIElementPerformAction(element, action.rawValue as CFString)
        guard result == .success else {
            throw RemoteError.axFailure(operation: action.rawValue, code: result.rawValue)
        }
    }

    private func read(_ attribute: UIAttribute) -> CFTypeRef? {
        var response: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute.rawValue as CFString, &response) == .success,
              let response else { return nil }
        return Self.presentValue(response)
    }

    private static func presentValue(_ value: CFTypeRef) -> CFTypeRef? {
        if value is NSNull { return nil }
        if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError {
            return nil
        }
        return value
    }
}
