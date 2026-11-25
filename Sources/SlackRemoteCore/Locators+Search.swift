extension Locators {
    static let searchWrapper = Locator(name: "searchWrapper", role: "AXGroup", classes: ["c-search_modal__wrapper"])
    static let searchQuery = Locator(name: "searchQuery", role: "AXComboBox", classes: ["ql-editor"])
    static let searchQuerySuggestionClass = "c-search_autocomplete__suggestion_item--query"
    static let searchFilterToken = "c-member_slug--search-filter"
    static let searchFilterPrefix = "quick-filter-"
    static let searchFilter = Locator(name: "searchFilter", role: "AXCheckBox", idPrefix: searchFilterPrefix)
}
