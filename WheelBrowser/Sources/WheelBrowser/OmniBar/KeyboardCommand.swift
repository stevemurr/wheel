import AppKit

/// Typed representation of NSResponder keyboard selectors used in the OmniBar.
enum KeyboardCommand {
    case moveUp
    case moveDown
    case submit
    case escape
    case tab
    case shiftTab
    case deleteBackward

    /// Converts an NSResponder selector to a typed `KeyboardCommand`, if recognized.
    static func from(selector: Selector) -> KeyboardCommand? {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            return .moveUp
        case #selector(NSResponder.moveDown(_:)):
            return .moveDown
        case #selector(NSResponder.insertNewline(_:)):
            return .submit
        case #selector(NSResponder.cancelOperation(_:)):
            return .escape
        case #selector(NSResponder.insertTab(_:)):
            return .tab
        case #selector(NSResponder.insertBacktab(_:)):
            return .shiftTab
        case #selector(NSResponder.deleteBackward(_:)):
            return .deleteBackward
        default:
            return nil
        }
    }
}
