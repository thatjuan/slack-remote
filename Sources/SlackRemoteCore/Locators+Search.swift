extension Locators {
    static let searchWrapper = Locator(name: "searchWrapper", role: "AXGroup", classes: ["c-search_modal__wrapper"])
    static let searchQuery = Locator(name: "searchQuery", role: "AXComboBox", classes: ["ql-editor"])
    static let searchClose = Locator(name: "searchClose", role: "AXButton", classes: ["c-search__input_and_close__close"])
    static let searchTopClear = Locator(name: "searchTopClear", role: "AXButton", classes: ["p-top_nav__search__clear"])
    static let searchQuerySuggestionClass = "c-search_autocomplete__suggestion_item--query"
    static let searchSuggestionSelected = "c-search_autocomplete__suggestion_item--pseudo-selected"
    static let searchFilterToken = "c-member_slug--search-filter"
    static let searchFilterPrefix = "quick-filter-"
    static let searchFilter = Locator(name: "searchFilter", role: "AXCheckBox", idPrefix: searchFilterPrefix)
    static let searchFilterActive = "c-filter-pill--active"

    static let scopedSearchHeader = Locator(name: "scopedSearchHeader", role: "AXGroup",
                                            classes: ["p-explorer_header", "p-explorer_header--search_in_channel"])
    static let scopedSearchList = Locator(name: "scopedSearchList", role: "AXList", subrole: "AXContentList",
                                          classes: ["c-virtual_list__scroll_container", "p-explorer_results__container"])
    static let scopedSearchMatches = Locator(name: "scopedSearchMatches", role: "AXList", subrole: "AXContentList",
                                             classes: ["c-virtual_list__scroll_container", "p-explorer_results__container--no-bottom-margin"])
    static let scopedSearchClose = Locator(name: "scopedSearchClose", role: "AXButton",
                                           classes: ["c-icon_button", "c-icon_button--size_medium", "c-icon_button--default"])
    static let scopedSearchEmptyID = "empty-results-state"
    static let scopedSearchLoadingID = "loading"
    static let scopedSearchActions = Locator(name: "scopedSearchActions", role: "AXGroup",
                                             classes: ["p-explorer_sections--title-actions--fixed"])
    static let scopedSearchExpand = Locator(name: "scopedSearchExpand", role: "AXButton",
                                            classes: ["c-link--button", "c-button-unstyled"])
    static let searchTimestamp = Locator(name: "searchTimestamp", role: "AXLink", classes: ["c-timestamp", "c-timestamp--static"])

    static let searchResults = Locator(name: "searchResults", role: "AXGroup", classes: ["p-view_contents--sidebar"])
    static let searchTab = Locator(name: "searchTab", role: "AXRadioButton", subrole: "AXTabButton",
                                   classes: ["c-tabs__tab"])
    static let searchTabSelected = "c-tabs__tab--active"
    static let searchResultList = Locator(name: "searchResultList", role: "AXList", subrole: "AXContentList") {
        $0.domClasses.contains(searchResultRow)
    }
    static let searchResultRow = "listitem__iBnNh"
    static let searchResultSortID = "search-filter-sort-filter"
    static let searchResultEmpty = "c-empty_state"
    static let searchSources = Locator(name: "searchSources", role: "AXPopUpButton", idPrefix: "search-filters-sources-filter")
    static let searchSourceMenu = Locator(name: "searchSourceMenu", role: "AXMenu", classes: ["c-menu__items"])
    static let searchSourceItem = Locator(name: "searchSourceItem", role: "AXMenuItem", classes: ["c-menu_item__button"])
    static let searchSourceChecked = "c-menu_item__button--checked"
    static let searchResultJump = Locator(name: "searchResultJump", role: "AXMenuItem",
                                          classes: ["p-message_actions_menu__jump"])
}
