import ApplicationServices
import Foundation

public struct NativeMenu {
    private let application: AXUIElement

    public init(slackApp: SlackApp) throws {
        _ = try slackApp.bundleURLForNavigation()
        application = AXUIElementCreateApplication(try SlackApp.requireRunning().processIdentifier)
    }

    /// Identify the native item by its shortcut, then invoke the item's AXPress action.
    public func press(cmdChar: String, modifiers: Int) throws {
        let name = "nativeMenuItem"
        guard let menuBar = attribute("AXMenuBar", of: application),
              CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            throw RemoteError.uiDrift(locator: name, found: 0)
        }
        var pending = children(of: unsafeDowncast(menuBar, to: AXUIElement.self))
        var matches: [AXNode] = []
        while let element = pending.popLast() {
            if attribute("AXRole", of: element) as? String == "AXMenuItem",
               attribute("AXMenuItemCmdChar", of: element) as? String == cmdChar,
               let number = attribute("AXMenuItemCmdModifiers", of: element),
               CFGetTypeID(number) == CFNumberGetTypeID(),
               (number as? NSNumber)?.intValue == modifiers {
                let node = AXNode(element)
                if node.bool(.enabled) == true { matches.append(node) }
            }
            pending.append(contentsOf: children(of: element))
        }
        guard matches.count == 1, let item = matches.first else {
            throw RemoteError.uiDrift(locator: name, found: matches.count)
        }
        do {
            try item.perform(.press)
        } catch {
            throw RemoteError.uiDrift(locator: name, found: 1)
        }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        attribute("AXChildren", of: element) as? [AXUIElement] ?? []
    }
}
