public struct Locator {
    public let name: String
    public let role: String
    public var subrole: String?
    public var classes: [String]
    public var idPrefix: String?
    private let requiredChild: ((any UINode) -> Bool)?

    public init(name: String, role: String, subrole: String? = nil,
                classes: [String] = [], idPrefix: String? = nil,
                requiredChild: ((any UINode) -> Bool)? = nil) {
        self.name = name
        self.role = role
        self.subrole = subrole
        self.classes = classes
        self.idPrefix = idPrefix
        self.requiredChild = requiredChild
    }

    public func matches(_ node: any UINode) -> Bool {
        node.role == role
            && (subrole == nil || node.subrole == subrole)
            && classes.allSatisfy(node.domClasses.contains)
            && (idPrefix.map { node.domID?.hasPrefix($0) == true } ?? true)
            && (requiredChild.map { node.children.contains(where: $0) } ?? true)
    }
}

public enum Locators {
    // Shell
    public static let webArea = Locator(name: "webArea", role: "AXWebArea")
    public static let sidebarRow = Locator(name: "sidebarRow", role: "AXRow", subrole: "AXOutlineRow",
                                           classes: ["p-channel_sidebar__static_list__item"])
    public static let sidebarRowTarget = Locator(name: "sidebarRowTarget", role: "AXGroup",
                                                  classes: ["p-channel_sidebar__channel"])
    public static let primaryView = Locator(name: "primaryView", role: "AXGroup",
                                             classes: ["p-view_contents--primary"])
    public static let secondaryView = Locator(name: "secondaryView", role: "AXGroup",
                                               classes: ["p-view_contents--secondary"])
    public static let sidebarRowSelected = "p-channel_sidebar__static_list__item--selected"
    public static let sidebarDraft = "p-channel_sidebar__channel--draft"

    // Overlays and account
    public static let modalContent = "ReactModal__Content"
    public static let modalOverlay = Locator(name: "modalOverlay", role: "AXGroup", classes: ["ReactModal__Overlay"])
    static let informationalTooltip = Locator(name: "informationalTooltip", role: "AXGroup",
                                               subrole: "AXUserInterfaceTooltip", classes: ["c-popover__content"])
    public static let selfDM = "p-channel_sidebar__channel--im-you"
    public static let searchButton = Locator(name: "searchButton", role: "AXButton", classes: ["p-top_nav__search"])
    static let searchModal = Locator(name: "searchModal", role: "AXGroup", classes: ["c-search_modal"])
    public static let searchClear = Locator(name: "searchClear", role: "AXButton",
                                             classes: ["c-search__input_box__clear"])
    public static let selfFilterPrefix = "quick-filter-from-"
    public static let selfFilter = Locator(name: "selfFilter", role: "AXCheckBox", idPrefix: selfFilterPrefix)

    // Messages
    // Slack's outer screen-reader list directly contains virtual message items or spacers.
    public static let messageList = Locator(name: "messageList", role: "AXList", subrole: "AXContentList",
                                             classes: ["sr-only"], requiredChild: messageItem.matches)
    public static let messageItem = Locator(name: "messageItem", role: "AXGroup",
                                             classes: ["c-virtual_list__item"], idPrefix: "message-list_")
    public static let messageListBottomID = "message-list_bottomSpacer"
    public static let messageBody = Locator(name: "messageBody", role: "AXGroup", subrole: "AXDocument",
                                             classes: ["c-message_kit__hover"])
    public static let senderButton = Locator(name: "senderButton", role: "AXButton",
                                              classes: ["c-message__sender_button"])
    public static let richTextSection = Locator(name: "richTextSection", role: "AXGroup",
                                                 classes: ["p-rich_text_section"])
    public static let reaction = Locator(name: "reaction", role: "AXCheckBox", subrole: "AXToggleButton",
                                          classes: ["c-reaction"])
    public static let reactionReacted = "c-reaction--reacted"
    public static let attachmentPrefix = "c-message_attachment"

    // Composer
    public static let composerEditor = Locator(name: "composerEditor", role: "AXTextArea", classes: ["ql-editor"])
    public static let sendButton = Locator(name: "sendButton", role: "AXButton",
                                            classes: ["c-wysiwyg_container__button--send"])
    public static let composerBlank = "ql-blank"
    public static let buttonDisabled = "c-button--disabled"
}
