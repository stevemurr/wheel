import Foundation
import SwiftUI

struct TabFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: String
    var tabIDs: [UUID]
    var lastActiveTabID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        color: String = Self.availableColors.first ?? "#007AFF",
        tabIDs: [UUID] = [],
        lastActiveTabID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.tabIDs = tabIDs
        self.lastActiveTabID = lastActiveTabID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var accentColor: Color {
        Color(hex: color) ?? .accentColor
    }

    mutating func touch() {
        updatedAt = Date()
    }

    static let availableColors: [String] = [
        "#007AFF",
        "#34C759",
        "#FF9500",
        "#FF3B30",
        "#AF52DE",
        "#FF2D55",
        "#5856D6",
        "#00C7BE",
        "#FFCC00",
        "#8E8E93"
    ]

    static func defaultName(for existingFolders: [TabFolder]) -> String {
        let base = "Folder"
        let existingNames = Set(existingFolders.map(\.name))

        if !existingNames.contains(base) {
            return base
        }

        for index in 2...999 {
            let candidate = "\(base) \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
        }

        return "\(base) \(UUID().uuidString.prefix(4))"
    }

    static func defaultColor(for existingFolders: [TabFolder]) -> String {
        let usedColors = existingFolders.map(\.color)
        for color in availableColors where !usedColors.contains(color) {
            return color
        }
        return availableColors[existingFolders.count % availableColors.count]
    }
}
