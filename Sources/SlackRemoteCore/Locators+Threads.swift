extension Locators {
    static let virtualItem = Locator(name: "virtualItem", role: "AXGroup", classes: ["c-virtual_list__item"])
    static let threadList = Locator(name: "threadList", role: "AXList", subrole: "AXContentList",
                                    requiredChild: { virtualItem.matches($0) && $0.domID?.contains(threadItemMarker) == true })
    static let threadItemMarker = "-thread-list-Thread_"
    static let contextMenuVisible = "c-virtual_list__item--contextmenu-visible"
    static let messageMenu = Locator(name: "messageMenu", role: "AXMenu", classes: ["c-menu__items"])
    static let openThread = Locator(name: "openThread", role: "AXMenuItem",
                                    classes: ["p-message_actions_menu__comment"])
    static let addReaction = Locator(name: "addReaction", role: "AXMenuItem",
                                     classes: ["p-message_actions_menu__add_reaction"])
    static let threadHeader = Locator(name: "threadHeader", role: "AXToolbar", classes: ["p-flexpane_header"])
    static let closeThread = Locator(name: "closeThread", role: "AXButton", classes: ["p-flexpane_header__control"])
    static let threadBroadcast = Locator(name: "threadBroadcast", role: "AXCheckBox", classes: ["c-input_checkbox"],
                                         idPrefix: "p-thread_footer__broadcast_checkbox--")
    static let emojiPicker = Locator(name: "emojiPicker", role: "AXGroup", classes: ["p-emoji_picker"])
    static let emojiCell = Locator(name: "emojiCell", role: "AXCell", classes: ["p-emoji_picker__list_item"])
    static let emojiSearch = Locator(name: "emojiSearch", role: "AXTextField", classes: ["p-emoji_picker__input"])
    static let emojiImage = Locator(name: "emojiImage", role: "AXImage", classes: ["c-emoji"])
    static let emojiGroup = Locator(name: "emojiGroup", role: "AXGroup", classes: ["c-emoji"])
    static let reactionCheckbox = Locator(name: "reaction", role: "AXCheckBox", classes: ["c-reaction"])
}
