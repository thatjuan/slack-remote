extension Locators {
    static let sidebarList = Locator(name: "sidebarList", role: "AXOutline",
                                     classes: ["c-virtual_list__scroll_container"],
                                     requiredChild: sidebarRow.matches)
    static let sidebarEndID = "addMoreChannels"
    static let sidebarGroupDM = "p-channel_sidebar__channel--mpim"
    static let addChannelsButton = Locator(name: "addChannelsButton", role: "AXPopUpButton")
    static let addChannelsMenuItem = Locator(name: "addChannelsMenuItem", role: "AXMenuItem",
                                             classes: ["c-menu_item__button"])
    // The two choices share their structural classes and have generated IDs.
    static func isBrowseChannels(_ item: any UINode) -> Bool {
        item.string(.title)?.localizedCaseInsensitiveCompare("Browse channels") == .orderedSame
    }

    static let directoryTabPanel = Locator(name: "directoryTabPanel", role: "AXGroup", subrole: "AXTabPanel",
                                            classes: ["c-tabs__tab_panel--active", "c-tabs__tab_panel--full_height"])
    static let directoryTab = Locator(name: "directoryTab", role: "AXRadioButton", subrole: "AXTabButton",
                                       classes: ["c-tabs__tab"])
    static let directoryChannels = Locator(name: "directoryChannels", role: "AXList",
                                            classes: ["p-explorer_results__container"])
    static let directoryChannelRow = Locator(name: "directoryChannelRow", role: "AXGroup",
                                              classes: ["p-explorer_results__contained-result"],
                                              requiredChild: {
        $0.domClasses.contains("c-channel_search_result")
    })
    static let directoryPeople = Locator(name: "directoryPeople", role: "AXTable",
                                          classes: ["p-explorer_grid"])
    static let directoryPeopleRow = Locator(name: "directoryPeopleRow", role: "AXRow", classes: ["p-grid__row"])
    static let directoryPersonCell = Locator(name: "directoryPersonCell", role: "AXCell",
                                              classes: ["p-explorer_grid__cell"])
    static let directoryPersonInfo = Locator(name: "directoryPersonInfo", role: "AXGroup",
                                              classes: ["p-browse_page_member_card_entity__info"])
    static let directoryPersonIDPrefix = "browse_page_member_info_"
    static let directoryText = Locator(name: "directoryText", role: "AXStaticText")

    static let conversationHeader = Locator(name: "conversationHeader", role: "AXToolbar",
                                             classes: ["p-view_header"])
    static let memberDetails = Locator(name: "memberDetails", role: "AXButton",
                                        classes: ["p-avatar_stack--details"])
    static let aboutModal = Locator(name: "aboutModal", role: "AXGroup",
                                     classes: [modalContent, "p-about_modal"])
    static let membersTab = Locator(name: "membersTab", role: "AXRadioButton", idPrefix: "members")
    static let activeTabClass = "c-tabs__tab--active"
    static let memberRow = Locator(name: "memberRow", role: "AXGroup",
                                    classes: ["p-ia_details_popover__members_list_item_member"])
    static let memberLabel = Locator(name: "memberLabel", role: "AXButton")
    static let aboutClose = Locator(name: "aboutClose", role: "AXButton",
                                      classes: ["c-sk-modal__close_button"])
}
