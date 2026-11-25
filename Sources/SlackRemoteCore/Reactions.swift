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
        let item = try target.locate(ts: ts, in: current, page: true)
        if try status(of: item, emoji: emoji).alreadyReacted {
            return Receipt(ts: ts, emoji: emoji, alreadyReacted: true)
        }

        let baseline: Status? = try Overlays.withModal(in: tree, deadline: deadline, opening: {
            let fresh = try SlackWindow.verify(view.destination, in: tree)
            _ = try target.openMenu(ts: ts, in: fresh)
            try requireIdle()
            try tree.refresh()
            let menu = try target.verifiedMenu(ts: ts, destination: view.destination)
            let control = try menu.one(Locators.addReaction)
            guard Date() < deadline else { throw RemoteError.timeout }
            try? control.perform(.press)
            let ready = try Poll.until(deadline) {
                try tree.refresh()
                if Overlays.open(in: tree).isEmpty { return nil as Bool? }
                let current = try SlackWindow.currentWindow(in: tree)
                let pickers = current.window.all(Locators.emojiPicker)
                if pickers.isEmpty { return nil }
                _ = try Overlays.requireOnlyModal(containing: Locators.emojiPicker, in: tree)
                return true
            }
            guard ready == true else { throw RemoteError.timeout }
        }) { modal in
            let picker = try modal.one(Locators.emojiPicker)
            let cellID = "emoji-picker-\(emoji)"
            if try cell(withID: cellID, in: picker) == nil {
                let search = try picker.one(Locators.emojiSearch)
                guard search.isSettable(.value) else {
                    throw RemoteError.uiDrift(locator: "emojiSearch.value", found: 0)
                }
                try requireIdle()
                guard Date() < deadline else { throw RemoteError.timeout }
                try search.set(.value, to: .string(emoji))
                let found = try Poll.until(min(deadline, Date().addingTimeInterval(2))) {
                    try tree.refresh()
                    let current = try Overlays.requireOnlyModal(containing: Locators.emojiPicker, in: tree)
                    return try cell(withID: cellID, in: current)
                }
                guard found != nil else { throw RemoteError.unsafeText(reason: "unknown emoji") }
            }

            try requireIdle()
            try tree.refresh()
            let fresh = try SlackWindow.verify(view.destination, in: tree, allowingModalContaining: Locators.emojiPicker)
            let item = try target.locate(ts: ts, in: fresh, page: false)
            let baseline = try status(of: item, emoji: emoji)
            if baseline.alreadyReacted { return nil }
            let current = try Overlays.requireOnlyModal(containing: Locators.emojiPicker, in: tree)
            guard let control = try cell(withID: cellID, in: current) else {
                throw RemoteError.uiDrift(locator: Locators.emojiCell.name, found: 0)
            }
            try Composer.requireLiveDestination(fresh)
            guard Date() < deadline else { throw RemoteError.timeout }
            try? control.perform(.press)
            let closed = try Poll.until(min(deadline, Date().addingTimeInterval(2))) {
                try tree.refresh()
                return Overlays.open(in: tree).isEmpty ? true : nil
            }
            guard closed == true else { throw RemoteError.reactionUnconfirmed }
            return baseline
        }
        guard let baseline else { return Receipt(ts: ts, emoji: emoji, alreadyReacted: true) }

        do {
            let confirmed = try Poll.until(deadline) {
                try tree.refresh()
                let fresh = try SlackWindow.verify(view.destination, in: tree)
                let item = try target.locate(ts: ts, in: fresh, page: false)
                let current = reactions(in: item)
                let own = current.filter(\.reacted)
                let confirmed = own.contains { $0.name == emoji }
                    || (!baseline.hasNames && !current.contains { $0.name != nil } && own.count > baseline.ownCount)
                return confirmed ? true : nil
            }
            if confirmed == true { return Receipt(ts: ts, emoji: emoji, alreadyReacted: false) }
        } catch {
            if !Overlays.open(in: tree).isEmpty { throw RemoteError.overlayLeftOpen }
        }
        throw RemoteError.reactionUnconfirmed
    }

    private struct Status {
        let alreadyReacted: Bool
        let hasNames: Bool
        let ownCount: Int
    }

    private static func reactions(in item: any UINode) -> [(name: String?, reacted: Bool)] {
        item.descendants().compactMap { reaction in
            let reacted = reaction.domClasses.contains(Locators.reactionReacted)
            // A reacted marker on an unexpected role still means a press could remove a reaction.
            guard Locators.reactionCheckbox.matches(reaction) else { return reacted ? (nil, true) : nil }
            let images = reaction.all(Locators.emojiImage)
            let name = images.count == 1 ? MessageText.emojiName(from: images.first?.string(.title)) : nil
            return (name, reacted)
        }
    }

    private static func status(of item: any UINode, emoji: String) throws -> Status {
        let all = reactions(in: item)
        let own = all.filter(\.reacted)
        let alreadyReacted = own.contains { $0.name == emoji }
        if !alreadyReacted, own.contains(where: { $0.name == nil }) {
            throw RemoteError.uiDrift(locator: "reactionEmojiIdentity", found: 0)
        }
        return Status(alreadyReacted: alreadyReacted, hasNames: all.contains { $0.name != nil }, ownCount: own.count)
    }

    private static func cell(withID id: String, in picker: any UINode) throws -> (any UINode)? {
        let cells = picker.all(Locators.emojiCell).filter { $0.domID == id }
        guard cells.count <= 1 else { throw RemoteError.uiDrift(locator: Locators.emojiCell.name, found: cells.count) }
        return cells.first
    }
}
