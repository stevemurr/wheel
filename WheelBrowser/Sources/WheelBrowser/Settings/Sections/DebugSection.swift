import SwiftUI

struct DebugSection: View {
    @State private var showClearHistoryAlert = false
    @State private var showClearReadingListAlert = false
    @State private var showClearSemanticIndexAlert = false

    var body: some View {
        Section("Debug") {
            Button(role: .destructive) {
                showClearHistoryAlert = true
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 20)
                    Text("Clear Browsing History")
                }
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                showClearReadingListAlert = true
            } label: {
                HStack {
                    Image(systemName: "bookmark.slash")
                        .frame(width: 20)
                    Text("Clear Reading List")
                }
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                showClearSemanticIndexAlert = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 20)
                    Text("Clear Semantic Index")
                }
            }
            .buttonStyle(.borderless)
        }
        .alert("Clear Browsing History?", isPresented: $showClearHistoryAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                BrowsingHistory.shared.clearHistory()
            }
        } message: {
            Text("This will permanently delete all browsing history. This action cannot be undone.")
        }
        .alert("Clear Reading List?", isPresented: $showClearReadingListAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    do {
                        let database = SearchDatabase.shared
                        try await database.initialize()
                        try await database.clearReadingList()
                    } catch {
                        Log.Settings.error("Failed to clear reading list: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("This will remove all items from your reading list. This action cannot be undone.")
        }
        .alert("Clear Semantic Index?", isPresented: $showClearSemanticIndexAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    do {
                        // Clear local SearchDatabase
                        let database = SearchDatabase.shared
                        try await database.initialize()
                        try await database.clearAllData()

                        // Clear native semantic search index
                        await SemanticSearchManagerV2.shared.clearIndex()
                    } catch {
                        Log.Settings.error("Failed to clear semantic index: \(error.localizedDescription)")
                    }
                }
            }
        } message: {
            Text("This will delete all indexed page data used for semantic search. This action cannot be undone.")
        }
    }
}
