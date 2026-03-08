import Foundation
import Testing
@testable import WheelBrowser

@Suite("OverlayWindowManager")
@MainActor
struct OverlayWindowManagerTests {
    @Test("Overlay windows maximize and restore their original frame")
    func maximizesAndRestores() {
        let manager = OverlayWindowManager.shared
        manager.closeAll()
        manager.containerSize = CGSize(width: 1280, height: 900)
        let url = URL(string: "https://example.com")!

        manager.openOverlay(url: url, title: "Example")
        let windowID = try! #require(manager.windows.first?.id)
        let originalPosition = try! #require(manager.windows.first?.position)
        let originalSize = try! #require(manager.windows.first?.size)

        manager.toggleMaximize(id: windowID, containerSize: manager.containerSize)
        #expect(manager.windows.first?.isMaximized == true)
        #expect(manager.windows.first?.size == manager.containerSize)

        manager.toggleMaximize(id: windowID, containerSize: manager.containerSize)
        #expect(manager.windows.first?.isMaximized == false)
        #expect(manager.windows.first?.position == originalPosition)
        #expect(manager.windows.first?.size == originalSize)

        manager.closeAll()
    }

    @Test("Overlay windows update position and size in place")
    func updatesFrame() {
        let manager = OverlayWindowManager.shared
        manager.closeAll()
        let url = URL(string: "https://example.com")!

        manager.openOverlay(url: url, title: "Example")
        let windowID = try! #require(manager.windows.first?.id)

        manager.updatePosition(id: windowID, position: CGPoint(x: 42, y: 64))
        manager.updateSize(id: windowID, size: CGSize(width: 540, height: 640))

        #expect(manager.windows.first?.position == CGPoint(x: 42, y: 64))
        #expect(manager.windows.first?.size == CGSize(width: 540, height: 640))

        manager.closeAll()
    }
}
