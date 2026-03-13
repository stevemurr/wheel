import SwiftUI

extension OmniBar: OmniBarKeyboardHandler {
    func handleKeyboardCommand(_ command: KeyboardCommand, moduleID: OmniBarModuleID, text: String) -> Bool {
        featureModel.handleKeyboardCommand(command, moduleID: moduleID, text: text)
    }
}
