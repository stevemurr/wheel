import SwiftUI

struct OmniBarModuleID: Hashable, RawRepresentable, ExpressibleByStringLiteral, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    static let address: Self = "address"
    static let semantic: Self = "semantic"
    static let agent: Self = "agent"
    static let readingList: Self = "readingList"
}

enum OmniBarModuleActivationReason: Equatable {
    case focusGain
    case modeSwitch
    case command
}

struct OmniBarFocusRequest: Equatable {
    let moduleID: OmniBarModuleID
    var prefill: String? = nil
    var selectAllInput: Bool = false
}

/// Represents which panel is currently visible (mutually exclusive)
enum OmniBarPanelVisibility: Equatable {
    case none
    case module(OmniBarModuleID)
    case downloads

    static let history: Self = .module(.address)
    static let semantic: Self = .module(.semantic)
    static let agent: Self = .module(.agent)
    static let readingList: Self = .module(.readingList)

    var moduleID: OmniBarModuleID? {
        if case .module(let moduleID) = self {
            return moduleID
        }
        return nil
    }
}

extension OmniBarModuleID {
    var correspondingPanel: OmniBarPanelVisibility {
        .module(self)
    }
}

@MainActor
protocol ListSelectable: AnyObject {
    var selectedIndex: Int { get set }
    var selectableCount: Int { get }
}

extension ListSelectable {
    func selectNext() {
        guard selectableCount > 0 else { return }
        if selectedIndex == -1 {
            selectedIndex = 0
        } else {
            selectedIndex = (selectedIndex + 1) % selectableCount
        }
    }

    func selectPrevious() {
        guard selectableCount > 0 else { return }
        if selectedIndex == -1 {
            selectedIndex = selectableCount - 1
        } else {
            selectedIndex = (selectedIndex - 1 + selectableCount) % selectableCount
        }
    }
}
