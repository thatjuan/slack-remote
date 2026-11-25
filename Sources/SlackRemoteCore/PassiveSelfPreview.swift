/// Binds a primary composer write to the attachment preview already visible in the configured self-DM.
struct PassiveSelfPreview {
    private let account: Account
    private let window: any UINode
    private let web: any UINode
    private let backdrop: any UINode
    private let popup: any UINode

    static func bind(_ destination: Destination, in tree: SlackTree, account: Account) throws -> VerifiedView {
        let (view, web) = try context(destination, in: tree, account: account)
        guard let overlay = try passiveOverlay(in: tree, web: web) else { throw RemoteError.uiBlocked }
        let binding = Self(account: account, window: view.window, web: web,
                           backdrop: overlay.backdrop, popup: overlay.popup)
        return binding.attaching(to: view)
    }

    func verify(_ destination: Destination, in tree: SlackTree) throws -> VerifiedView {
        let (view, web) = try Self.context(destination, in: tree, account: account)
        guard Self.sameElement(window, view.window), Self.sameElement(self.web, web) else {
            throw RemoteError.uiBlocked
        }
        if let overlay = try Self.passiveOverlay(in: tree, web: web) {
            guard Self.sameElement(backdrop, overlay.backdrop), Self.sameElement(popup, overlay.popup) else {
                throw RemoteError.uiBlocked
            }
        }
        return attaching(to: view)
    }

    private func attaching(to view: VerifiedView) -> VerifiedView {
        VerifiedView(destination: view.destination, window: view.window, primaryView: view.primaryView,
                     passiveSelfPreview: self)
    }

    private static func context(_ destination: Destination, in tree: SlackTree, account: Account)
        throws -> (VerifiedView, any UINode) {
        guard account.team == destination.team, account.selfDM == destination.conversation,
              tree.windows.count == 1, let view = try? SlackWindow.verifyForReading(destination, in: tree),
              view.window.role == "AXWindow", view.window.subrole == "AXStandardWindow", view.window.bool(.modal) != true,
              let web = try? view.window.one(Locators.webArea), web.subrole == nil,
              web.string(.url) == "https://app.slack.com/client/\(destination.team.rawValue)/\(destination.conversation.rawValue)",
              (try? Account.sidebarSelfDM(in: view.window)) == account.selfDM,
              view.window.all(Locators.sidebarRow).filter({ $0.domClasses.contains(Locators.sidebarRowSelected) }).count == 1,
              view.window.all(Locators.secondaryView).isEmpty,
              view.primaryView.all(Locators.messageList).count == 1,
              let editor = try? view.primaryView.one(Locators.composerEditor), editor.bool(.enabled) == true,
              editor.isSettable(.value), editor.bool(.focused) == true, let value = editor.string(.value),
              !editor.domClasses.contains(Locators.composerBlank) || MessageText.normalize(value).isEmpty,
              let send = try? view.primaryView.one(Locators.sendButton),
              send.actionNames.contains(UIAction.press.rawValue) else { throw RemoteError.uiBlocked }
        return (view, web)
    }

    private static func passiveOverlay(in tree: SlackTree, web: any UINode)
        throws -> (backdrop: any UINode, popup: any UINode)? {
        let nodes = tree.windows.flatMap { $0.descendants() }
        guard !nodes.contains(where: { $0.role == "AXDialog" || $0.subrole == "AXApplicationDialog" }) else {
            throw RemoteError.uiBlocked
        }
        let overlays = nodes.compactMap(Overlays.kind)
        if overlays.isEmpty { return nil }
        guard overlays == [.modal], web.all(Locators.modalOverlay).count == 1,
              let overlay = Overlays.attachmentPopover(in: web),
              overlay.backdrop.bool(.focused) == false else { throw RemoteError.uiBlocked }
        let previewNodes = [overlay.backdrop] + overlay.backdrop.descendants()
        guard previewNodes.allSatisfy({ node in
            node.bool(.modal) != true && node.node(.cancelButton) == nil && node.node(.defaultButton) == nil
                && !node.isSettable(.value) && (node.role != "AXStaticText" || node.children.isEmpty)
        }) else { throw RemoteError.uiBlocked }
        return overlay
    }

    private static func sameElement(_ first: any UINode, _ second: any UINode) -> Bool {
        if let first = first as? AXNode, let second = second as? AXNode {
            return first.referencesSameElement(as: second)
        }
        return first as AnyObject === second as AnyObject
    }
}
