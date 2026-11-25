import Foundation

public enum Inspector {
    public enum Scope: String, CaseIterable { case window, primary, secondary, modal, sheet }

    public static func describe(_ window: any UINode, scope: Scope, maxDepth: Int?, emojiNames: Bool = false) -> String {
        let roots: [any UINode]
        switch scope {
        case .window: roots = [window]
        case .primary: roots = scopedNodes(in: window, matching: Locators.primaryView.matches)
        case .secondary: roots = scopedNodes(in: window, matching: Locators.secondaryView.matches)
        case .modal: roots = scopedNodes(in: window) { Overlays.kind($0) == .modal }
        case .sheet: roots = scopedNodes(in: window) { Overlays.kind($0) == .sheet }
        }
        var lines: [String] = []
        var pending = roots.reversed().map { (node: $0, depth: 0) }
        while let (node, depth) = pending.popLast() {
            var fields = [node.role]
            if let subrole = node.subrole { fields.append(subrole) }
            if !node.domClasses.isEmpty { fields.append("classes=" + node.domClasses.map(mask).joined(separator: " ")) }
            if let id = node.domID { fields.append("id=" + mask(id)) }
            if !node.actionNames.isEmpty { fields.append("actions=" + node.actionNames.joined(separator: ",")) }
            let settable = [UIAttribute.value, .focused, .selectedText].filter(node.isSettable)
            if !settable.isEmpty { fields.append("settable=" + settable.map(\.rawValue).joined(separator: ",")) }
            if emojiNames, Locators.emojiImage.matches(node),
               let name = MessageText.emojiName(from: node.string(.title)) {
                fields.append("title=:\(name):")
            }
            lines.append(String(repeating: "  ", count: depth) + fields.joined(separator: " "))
            if canDescend(node), maxDepth.map({ depth < $0 }) ?? true {
                pending.append(contentsOf: node.children.reversed().map { ($0, depth + 1) })
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private static func scopedNodes(in root: any UINode, matching: (any UINode) -> Bool) -> [any UINode] {
        var pending = [root]
        var matches: [any UINode] = []
        while let node = pending.popLast() {
            if matching(node) { matches.append(node) }
            if canDescend(node) { pending.append(contentsOf: node.children.reversed()) }
        }
        return matches
    }

    private static func canDescend(_ node: any UINode) -> Bool {
        node.role != "AXTextArea" && node.role != "AXComboBox"
    }

    private static func mask(_ value: String) -> String {
        value.replacing(#/[A-Z][A-Z0-9]{7,}|[0-9]{6,}/#) { match in
            "\(match.output.first!)§\(match.output.count)"
        }
    }
}
