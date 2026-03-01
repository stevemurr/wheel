import Foundation

extension AppSettings {

    // MARK: - Category Convenience Methods

    /// Check if a blocking category is enabled
    @MainActor
    func isBlockingCategoryEnabled(_ category: BlockingCategory) -> Bool {
        guard adBlockingEnabled else { return false }
        return ContentBlockerManager.shared.isEnabled(category)
    }

    /// Toggle a blocking category
    @MainActor
    func toggleBlockingCategory(_ category: BlockingCategory) {
        ContentBlockerManager.shared.toggle(category)
        // If any category is now enabled, ensure master toggle is on
        if !ContentBlockerManager.shared.enabledCategories.isEmpty {
            adBlockingEnabled = true
        }
    }

    /// Set all blocking categories at once
    @MainActor
    func setBlockingCategories(_ categories: Set<BlockingCategory>) {
        if categories.isEmpty {
            adBlockingEnabled = false
        } else {
            adBlockingEnabled = true
            ContentBlockerManager.shared.enabledCategories = categories
        }
    }
}
