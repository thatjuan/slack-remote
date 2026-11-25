extension Locators {
    static let attachButton = Locator(name: "attachButton", role: "AXPopUpButton",
                                      classes: ["c-wysiwyg_container__button--shortcuts"])
    static let attachMenu = Locator(name: "attachMenu", role: "AXMenu", classes: ["c-menu__items"])
    static let attachItem = Locator(name: "attachItem", role: "AXMenuItem", classes: ["c-menu_item__button"])
    static let fileSheet = Locator(name: "fileSheet", role: "AXSheet")
    static let fileSidebar = Locator(name: "fileSidebar", role: "AXOutline")
    static let fileBrowser = Locator(name: "fileBrowser", role: "AXBrowser")
    static let fileSearch = Locator(name: "fileSearch", role: "AXSearchField")

    static let pendingFile = Locator(name: "pendingFile", role: "AXGroup", classes: ["c-file_upload"])
    static let pendingFileName = Locator(name: "pendingFileName", role: "AXStaticText",
                                         classes: ["c-file_upload__title"])
    static let removePendingFile = Locator(name: "removePendingFile", role: "AXButton",
                                           classes: ["c-file_upload__remove"])
    static let sentFileName = Locator(name: "sentFileName", role: "AXStaticText", classes: ["c-file__title"])
}
