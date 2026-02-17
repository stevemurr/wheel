import Foundation

/// Represents a workspace that groups tabs together with an optional assigned agent
struct Workspace: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String  // SF Symbol name
    var color: String // Hex color for accent
    var tabIDs: [UUID]  // References to tabs in this workspace
    var defaultAgentID: UUID?  // The agent assigned to this workspace
    var createdAt: Date
    var lastAccessedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder",
        color: String = "#007AFF",
        tabIDs: [UUID] = [],
        defaultAgentID: UUID? = nil,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.tabIDs = tabIDs
        self.defaultAgentID = defaultAgentID
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Helpers

extension Workspace {
    /// Converts the hex color string to a Color
    var accentColor: Color {
        Color(hex: color) ?? .blue
    }

    /// Predefined workspace colors for selection
    static let availableColors: [String] = [
        "#007AFF", // Blue
        "#34C759", // Green
        "#FF9500", // Orange
        "#FF3B30", // Red
        "#AF52DE", // Purple
        "#FF2D55", // Pink
        "#5856D6", // Indigo
        "#00C7BE", // Teal
        "#FFCC00", // Yellow
        "#8E8E93"  // Gray
    ]

    /// Predefined workspace icons for selection
    static let availableIcons: [String] = [
        "folder",
        "briefcase",
        "house",
        "building.2",
        "cart",
        "book",
        "gamecontroller",
        "music.note",
        "film",
        "photo",
        "paintbrush",
        "hammer",
        "wrench.and.screwdriver",
        "terminal",
        "globe",
        "airplane",
        "car",
        "heart",
        "star",
        "bookmark"
    ]
}

// MARK: - Color Extension for Hex Support

import SwiftUI

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
