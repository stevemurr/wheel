import SwiftUI

enum AppAnimation {
    static let quick = Animation.easeInOut(duration: 0.1)
    static let standard = Animation.easeInOut(duration: 0.15)
    static let springStandard = Animation.spring(response: 0.3, dampingFraction: 0.8)
}
