extension Locators {
    static let attachButton = Locator(name: "attachButton", role: "AXPopUpButton",
                                      classes: ["c-wysiwyg_container__button--shortcuts"])
    static let attachMenu = Locator(name: "attachMenu", role: "AXMenu", classes: ["c-menu__items"])
    static let attachItem = Locator(name: "attachItem", role: "AXMenuItem", classes: ["c-menu_item__button"])
    static let attachItemLabel = Locator(name: "attachItemLabel", role: "AXGroup", classes: ["c-menu_item__label"])
    static let fileSheet = Locator(name: "fileSheet", role: "AXSheet")
    static let fileSidebar = Locator(name: "fileSidebar", role: "AXOutline")
    static let fileBrowser = Locator(name: "fileBrowser", role: "AXBrowser")
    static let pendingFile = Locator(name: "pendingFile", role: "AXGroup", classes: ["p-pending_file"])
    static let removePendingFile = Locator(name: "removePendingFile", role: "AXButton",
                                           classes: ["p-multi_file_upload__file_status_btn--remove"])
    static let sentFile = Locator(name: "sentFile", role: "AXGroup", classes: ["p-message_file"])
    static let sentFileContainer = Locator(name: "sentFileContainer", role: "AXGroup", classes: ["c-message_kit__file"])
}
