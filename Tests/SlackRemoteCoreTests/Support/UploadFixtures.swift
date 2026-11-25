import Foundation
@testable import SlackRemoteCore
import Testing

final class UploadFixture {
    let staged = URL(fileURLWithPath: "/Downloads/slack-remote-upload-SYNTHETIC/generated.txt")
    let view: ComposerFixture
    let composer: ComposerFixture
    let thread: ThreadFixture?
    let attach = FakeNode(role: "AXPopUpButton", domClasses: Locators.attachButton.classes)
    let popup = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent])
    let backdrop = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
    let open = FakeNode(role: "AXButton", attributes: [.enabled: .bool(true)])
    let cancel = FakeNode(role: "AXButton")
    let sheet: FakeNode
    let sidebar: FakeNode
    let browser: FakeNode
    let wrong: FakeNode
    let file: FakeNode
    let remove = FakeNode(role: "AXButton", domClasses: Locators.removePendingFile.classes)
    let scope: FakeNode

    var pendingName: String?
    var removeAllowed = true
    var openedFile: (() -> Void)?
    var beforeOpen: (() -> Void)?

    init(thread: ThreadFixture? = nil) throws {
        self.thread = thread
        view = try thread?.primary ?? ComposerFixture()
        composer = thread?.threadComposer ?? view
        scope = try thread?.pane ?? #require(try view.window.one(Locators.primaryView) as? FakeNode)
        scope.children.append(attach)
        file = Self.row(staged)
        wrong = Self.row(staged.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(staged.lastPathComponent))
        let directory = Self.row(staged.deletingLastPathComponent())
        let downloads = Self.row(staged.deletingLastPathComponent().deletingLastPathComponent())
        sidebar = FakeNode(role: "AXOutline", children: [downloads])
        browser = FakeNode(role: "AXBrowser")
        sheet = FakeNode(role: "AXSheet", children: [sidebar, browser, open, cancel])
        sheet.nodeAttributes = [.cancelButton: cancel, .defaultButton: open]
        downloads.onSet = { [weak self] _, _ in self?.browser.children = [self?.wrong, directory].compactMap { $0 } }
        directory.onSet = { [weak self] _, _ in
            guard let self else { return }
            browser.children = [wrong, file]
        }
        let menuItems = (0..<4).map {
            FakeNode(role: "AXMenuItem", domClasses: Locators.attachItem.classes, domID: "menu-8-\($0)")
        }
        menuItems.last?.children = [
            FakeNode(role: "AXGroup", domClasses: Locators.attachItemLabel.classes, children: [
                FakeNode(role: "AXStaticText", attributes: [.value: .string("Upload from your computer")]),
            ]),
        ]
        let menu = FakeNode(role: "AXMenu", domClasses: Locators.attachMenu.classes, children: menuItems)
        popup.children = [menu]
        attach.onPerform = { [weak self] _ in
            guard let self else { return }
            view.webArea.children.append(contentsOf: [backdrop, popup])
        }
        backdrop.onPerform = { [weak self] _ in self?.dismissMenu() }
        menuItems.last?.actionNames = [UIAction.press.rawValue]
        remove.actionNames = [UIAction.press.rawValue]
        menuItems.last?.onPerform = { [weak self] _ in
            guard let self else { return }
            dismissMenu()
            beforeOpen?()
            view.window.children.append(sheet)
        }
        cancel.onPerform = { [weak self] _ in self?.dismissSheet() }
        open.onPerform = { [weak self] _ in
            guard let self else { return }
            dismissSheet()
            installPending()
            openedFile?()
        }
        composer.editor.onSet = { [weak self] attribute, value in
            if attribute == .value, case .string(let text) = value { self?.composer.show(.text(text)) }
        }
    }

    private static func row(_ url: URL) -> FakeNode {
        let row = FakeNode(role: "AXRow", attributes: [.url: .string(url.absoluteString), .selected: .bool(false)])
        row.settableAttributes = [.selected]
        return row
    }

    private func dismissMenu() {
        view.webArea.children.removeAll { node in
            let fake = node as? FakeNode
            return fake === popup || fake === backdrop
        }
    }

    private func dismissSheet() {
        view.window.children.removeAll { ($0 as? FakeNode) === sheet }
    }

    private func installPending() {
        let name = pendingName ?? staged.lastPathComponent
        let pending = FakeNode(role: "AXGroup", domClasses: Locators.pendingFile.classes, children: [remove],
                               attributes: [.title: .string(name), .description: .string(name)])
        scope.children.append(pending)
        composer.show(.pendingContent)
        remove.onPerform = { [weak self, weak pending] _ in
            guard let self, removeAllowed else { return }
            scope.children.removeAll { ($0 as? FakeNode) === pending }
            composer.show(.empty)
        }
    }

    func appearSent(text: String?, name: String? = nil) {
        scope.children.removeAll(where: Locators.pendingFile.matches)
        composer.show(.empty)
        let item = MessageFixtures.message(1, sections: text.map { [[MessageFixtures.text($0)]] } ?? [])
        let attributes: [UIAttribute: UIValue] = name.map { [.title: .string($0), .description: .string($0)] } ?? [:]
        let attachment = FakeNode(role: "AXGroup", domClasses: Locators.sentFile.classes, attributes: attributes)
        (try? item.one(Locators.messageBody) as? FakeNode)?.children.append(attachment)
        if let thread {
            item.domID = VerifiedThread.itemPrefix(view.view.destination, rootTs: ThreadFixture.root) + ThreadFixture.reply
            thread.list.children.insert(item, at: thread.list.children.count - 1)
        } else {
            view.list.children.append(item)
        }
    }

    func upload(tree: SlackTree? = nil, text: String? = nil, deadline: TimeInterval = 0.5) throws
        -> Uploader.Receipt {
        let messageScope = try thread.map { try MessageScope.thread($0.verify()) } ?? .primary
        return try Uploader(view: view.view, scope: messageScope, in: tree ?? view.tree, requireIdle: {})
            .uploadStaged(staged, text: text, alsoSendToChannel: false, deadline: Date().addingTimeInterval(deadline))
    }

    func attachFile(deadline: Date = Date().addingTimeInterval(0.5)) throws {
        try FilePanel(tree: view.tree, destination: view.view.destination, requireIdle: {})
            .attach(staged, deadline: deadline, opening: { try attach.perform(.press) }, openingFile: {})
    }
}
