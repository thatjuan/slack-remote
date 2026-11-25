extension Locators {
    static let sidebarList = Locator(name: "sidebarList", role: "AXOutline",
                                     classes: ["c-virtual_list__scroll_container"],
                                     requiredChild: sidebarRow.matches)
    static let sidebarEndID = "addMoreChannels"
    static let sidebarGroupDM = "p-channel_sidebar__channel--mpim"

    static let conversationHeader = Locator(name: "conversationHeader", role: "AXToolbar",
                                             classes: ["p-view_header"])
    static let memberDetails = Locator(name: "memberDetails", role: "AXButton",
                                        classes: ["p-avatar_stack--details"])
    static let aboutModal = Locator(name: "aboutModal", role: "AXGroup",
                                     classes: [modalContent, "p-about_modal"])
    static let membersTab = Locator(name: "membersTab", role: "AXRadioButton", idPrefix: "members")
    static let memberRow = Locator(name: "memberRow", role: "AXGroup",
                                    classes: ["p-ia_details_popover__members_list_item_member"])
    static let memberLabel = Locator(name: "memberLabel", role: "AXButton")
    static let aboutClose = Locator(name: "aboutClose", role: "AXButton",
                                      classes: ["c-sk-modal__close_button"])
}
