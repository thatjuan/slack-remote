import Foundation

public enum Reactions {
    public struct Receipt: Encodable {
        public let ts: String
        public let emoji: String
        public let reacted = true
        public let alreadyReacted: Bool
    }

    public static func add(_ emoji: String, to ts: String, in view: VerifiedView, scope: MessageScope = .primary,
                           tree: SlackTree, deadline: Date, requireIdle: @escaping () throws -> Void) throws -> Receipt {
        guard MessageText.isEmojiName(emoji) else { throw RemoteError.unsafeText(reason: "invalid_emoji_name") }
        let target = MessageTarget(in: tree, scope: scope, deadline: deadline, requireIdle: requireIdle)
        try tree.refresh()
        let current = try SlackWindow.verify(view.destination, in: tree)
        _ = try target.locate(ts: ts, in: current, page: true)
        try tree.refresh()
        let fresh = try SlackWindow.verify(view.destination, in: tree)
        let item = try target.locate(ts: ts, in: fresh, page: false)
        if try alreadyReacted(emoji, on: item) {
            return Receipt(ts: ts, emoji: emoji, alreadyReacted: true)
        }
        let binding = try ClientBinding(fresh)
        let menu = try target.openMenu(ts: ts, in: fresh)
        var ownedPicker: (any UINode)?
        var pressed = false
        let result = Result {
            try requireIdle()
            try tree.refresh()
            _ = try binding.verify(in: tree)
            let markedMenu = try target.verifiedMenu(ts: ts, destination: fresh.destination)
            guard sameElement(menu, markedMenu) else { throw RemoteError.uiDrift(locator: "messageMenuIdentity", found: 0) }
            let menuView = try SlackWindow.verify(fresh.destination, in: tree, allowingModalContaining: Locators.messageMenu)
            let menuItem = try target.locate(ts: ts, in: menuView, page: false)
            if try alreadyReacted(emoji, on: menuItem) { return }

            let add = try markedMenu.one(Locators.addReaction)
            try requirePressable(add, locator: Locators.addReaction)
            guard Date() < deadline else { throw RemoteError.timeout }
            let opening = Result { try add.perform(.press) }
            let openPicker = try Poll.until(min(deadline, Date().addingTimeInterval(3))) {
                try tree.refresh()
                try binding.verify(in: tree, allowHiddenAccount: true)
                if Overlays.open(in: tree).isEmpty { return nil as (any UINode)? }
                if let stillOpen = try? Overlays.requireOnlyModal(containing: Locators.messageMenu, in: tree) {
                    guard sameElement(menu, stillOpen),
                          (try? target.verifiedMenu(ts: ts, destination: fresh.destination)) != nil else {
                        throw RemoteError.uiDrift(locator: "messageMenuIdentity", found: 0)
                    }
                    return nil
                }
                let picker = try Overlays.requireOnlyModal(containing: Locators.emojiPicker, in: tree)
                // The sole picker is the observed replacement for the exact message's menu.
                ownedPicker = picker
                return picker
            }
            guard let openPicker else { throw RemoteError.timeout }
            try opening.get()

            let search = try openPicker.one(Locators.emojiSearch)
            guard search.isSettable(.value) else { throw RemoteError.uiDrift(locator: "emojiSearch.value", found: 0) }
            try requireIdle()
            guard Date() < deadline else { throw RemoteError.timeout }
            try search.set(.value, to: .string(emoji))

            let cellID = "emoji-picker-\(emoji)"
            var seen = 0
            let found = try Poll.until(min(deadline, Date().addingTimeInterval(2))) {
                try tree.refresh()
                let picker = try boundPicker(openPicker, binding: binding, in: tree)
                seen = matchingCells(cellID, in: picker).count
                return try searchResult(cellID, query: emoji, in: picker)
            }
            guard found != nil else {
                if seen > 0 { throw RemoteError.uiDrift(locator: Locators.emojiCell.name, found: seen) }
                throw RemoteError.unsafeText(reason: "unknown emoji")
            }

            try requireIdle()
            try tree.refresh()
            let picker = try boundPicker(openPicker, binding: binding, in: tree)
            let client = try SlackWindow.currentWindow(in: tree)
            if !client.window.all(Locators.primaryView).isEmpty {
                let live = try SlackWindow.verify(fresh.destination, in: tree, allowingModalContaining: Locators.emojiPicker)
                let liveTarget = try target.locate(ts: ts, in: live, page: false)
                if try alreadyReacted(emoji, on: liveTarget) { return }
            } else if binding.account == nil {
                // The picker can hide the target and sidebar. Require a pre-transition account marker.
                throw RemoteError.accountUnverified
            }
            guard let control = try searchResult(cellID, query: emoji, in: picker) else {
                throw RemoteError.uiDrift(locator: Locators.emojiCell.name, found: 0)
            }
            try requirePressable(control, locator: Locators.emojiCell)
            guard Date() < deadline else { throw RemoteError.timeout }

            pressed = true
            try? control.perform(.press)
            let closed = try Poll.until(min(deadline, Date().addingTimeInterval(2))) {
                try tree.refresh()
                if Overlays.open(in: tree).isEmpty { return true }
                _ = try boundPicker(openPicker, binding: binding, in: tree)
                return nil
            }
            guard closed == true else { throw RemoteError.reactionUnconfirmed }
        }
        try closeOwnedPopup(picker: ownedPicker, menu: menu, binding: binding, in: tree)
        do {
            try result.get()
        } catch {
            if pressed { throw RemoteError.reactionUnconfirmed }
            throw error
        }
        guard pressed else { return Receipt(ts: ts, emoji: emoji, alreadyReacted: true) }

        do {
            let confirmed = try Poll.until(deadline) {
                try tree.refresh()
                _ = try binding.verify(in: tree)
                let confirmedView = try SlackWindow.verify(fresh.destination, in: tree)
                let confirmedItem = try target.locate(ts: ts, in: confirmedView, page: false)
                return namedOwnReactions(in: confirmedItem).contains { $0 == emoji } ? true : nil
            }
            if confirmed == true { return Receipt(ts: ts, emoji: emoji, alreadyReacted: false) }
        } catch {
            if !Overlays.open(in: tree).isEmpty { throw RemoteError.overlayLeftOpen }
        }
        throw RemoteError.reactionUnconfirmed
    }

    private struct ClientBinding {
        let window: any UINode
        let webArea: any UINode
        let url: String
        let account: ConversationID?

        init(_ view: VerifiedView) throws {
            window = view.window
            webArea = try window.one(Locators.webArea)
            guard let url = webArea.string(.url), ClientLocation.parse(url: url).destination == view.destination else {
                throw RemoteError.uiDrift(locator: "reactionClientURL", found: 0)
            }
            self.url = url
            account = try Account.sidebarSelfDM(in: window)
        }

        @discardableResult
        func verify(in tree: SlackTree, allowHiddenAccount: Bool = false) throws -> ClientWindow {
            let current = try SlackWindow.currentWindow(in: tree)
            let currentWebArea = try current.window.one(Locators.webArea)
            guard sameElement(window, current.window), sameElement(webArea, currentWebArea),
                  currentWebArea.string(.url) == url else {
                throw RemoteError.uiDrift(locator: "reactionClientIdentity", found: 0)
            }
            let visibleAccount = try Account.sidebarSelfDM(in: current.window)
            let sidebarHidden = current.window.all(Locators.sidebarRow).isEmpty
            guard visibleAccount == account || (allowHiddenAccount && visibleAccount == nil && sidebarHidden) else {
                throw RemoteError.accountMismatch
            }
            return current
        }
    }

    private static func sameElement(_ first: any UINode, _ second: any UINode) -> Bool {
        if let first = first as? AXNode, let second = second as? AXNode {
            return first.referencesSameElement(as: second)
        }
        return (first as AnyObject) === (second as AnyObject)
    }

    private static func requirePressable(_ node: any UINode, locator: Locator) throws {
        guard node.bool(.enabled) == true, node.actionNames.contains(UIAction.press.rawValue) else {
            throw RemoteError.uiDrift(locator: locator.name, found: 0)
        }
    }

    private static func boundPicker(_ expected: any UINode, binding: ClientBinding, in tree: SlackTree) throws
        -> any UINode {
        _ = try binding.verify(in: tree, allowHiddenAccount: true)
        let picker = try Overlays.requireOnlyModal(containing: Locators.emojiPicker, in: tree)
        guard sameElement(expected, picker) else { throw RemoteError.uiDrift(locator: "emojiPickerIdentity", found: 0) }
        return picker
    }

    private static func closeOwnedPopup(picker: (any UINode)?, menu: any UINode, binding: ClientBinding,
                                        in tree: SlackTree) throws {
        do {
            try tree.refresh()
            guard !Overlays.open(in: tree).isEmpty else { return }
            let current = try binding.verify(in: tree, allowHiddenAccount: picker != nil)
            let locator = picker == nil ? Locators.messageMenu : Locators.emojiPicker
            let control = try Overlays.requireOnlyModal(containing: locator, in: tree)
            guard sameElement(picker ?? menu, control) else { throw RemoteError.overlayLeftOpen }

            let backdrops = current.window.all(Locators.modalOverlay).filter {
                $0.all(Locators.informationalTooltip).isEmpty
            }
            guard backdrops.count == 1, let backdrop = backdrops.first else { throw RemoteError.overlayLeftOpen }
            try? backdrop.perform(.press)
            let closed = try Poll.until(Date().addingTimeInterval(1.5)) {
                try tree.refresh()
                _ = try binding.verify(in: tree, allowHiddenAccount: true)
                return Overlays.open(in: tree).isEmpty ? true : nil
            }
            guard closed == true else { throw RemoteError.overlayLeftOpen }
        } catch {
            throw RemoteError.overlayLeftOpen
        }
    }

    private static func namedOwnReactions(in item: any UINode) -> [String?] {
        var own: [String?] = []
        for reaction in item.descendants() {
            let isCheckbox = Locators.reactionCheckbox.matches(reaction)
            let marked = reaction.domClasses.contains(Locators.reactionReacted)
            let checked = isCheckbox && reaction.bool(.value) == true
            guard marked || checked else { continue }
            guard marked, checked else {
                own.append(nil)
                continue
            }
            let images = reaction.descendants().filter {
                Locators.emojiImage.matches($0) || Locators.emojiGroup.matches($0)
            }
            guard images.count == 1, let image = images.first else {
                own.append(nil)
                continue
            }
            let name = MessageText.renderedEmojiName(image)
                ?? image.string(.title)?.wholeMatch(of: #/([a-z0-9_+'-]+) emoji/#).map { String($0.1) }
            own.append(name)
        }
        return own
    }

    private static func alreadyReacted(_ emoji: String, on item: any UINode) throws -> Bool {
        let own = namedOwnReactions(in: item)
        if own.contains(emoji) { return true }
        guard !own.contains(nil) else { throw RemoteError.uiDrift(locator: "reactionEmojiIdentity", found: 0) }
        return false
    }

    private static func matchingCells(_ id: String, in picker: any UINode) -> [any UINode] {
        var cells: [any UINode] = []
        for cell in picker.all(Locators.emojiCell) where cell.domID == id {
            // Tables expose the same native cell through both the AXRow and AXColumn.
            if !cells.contains(where: { sameElement($0, cell) }) { cells.append(cell) }
        }
        return cells
    }

    private static func searchResult(_ id: String, query: String, in picker: any UINode) throws -> (any UINode)? {
        guard try picker.one(Locators.emojiSearch).string(.value) == query else { return nil }
        let matching = matchingCells(id, in: picker)
        guard matching.count == 1, let cell = matching.first else { return nil }
        let table = try picker.one(Locators.emojiResults).one(Locators.emojiResultsTable)
        let rows = table.children.filter(Locators.emojiResultsRow.matches)
        let canonical = rows.flatMap(\.children).filter {
            Locators.emojiCell.matches($0) && $0.domID == id && sameElement($0, cell)
        }
        return canonical.count == 1 ? canonical.first : nil
    }
}
