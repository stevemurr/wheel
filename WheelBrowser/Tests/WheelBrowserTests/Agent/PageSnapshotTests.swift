import Testing
@testable import WheelBrowser

@Suite("ActionDelta / PageSnapshot Tests")
struct PageSnapshotTests {

    // MARK: - significantDOMChange with -1 sentinel

    @Test("significantDOMChange returns false when elementCountBefore is -1")
    func significantDOMChangeNegativeBefore() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: -1, elementCountAfter: 50,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(!delta.significantDOMChange)
    }

    @Test("significantDOMChange returns false when elementCountAfter is -1")
    func significantDOMChangeNegativeAfter() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: 50, elementCountAfter: -1,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(!delta.significantDOMChange)
    }

    @Test("significantDOMChange returns false when both counts are -1")
    func significantDOMChangeBothNegative() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: -1, elementCountAfter: -1,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(!delta.significantDOMChange)
    }

    @Test("significantDOMChange detects large absolute change")
    func significantDOMChangeLargeAbsolute() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: 10, elementCountAfter: 20,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(delta.significantDOMChange)
    }

    @Test("significantDOMChange detects large relative change (>30%)")
    func significantDOMChangeLargeRelative() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: 10, elementCountAfter: 14,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(delta.significantDOMChange)
    }

    @Test("significantDOMChange returns false for small change")
    func significantDOMChangeSmall() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: 50, elementCountAfter: 52,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(!delta.significantDOMChange)
    }

    @Test("significantDOMChange returns false for identical counts")
    func significantDOMChangeIdentical() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: 30, elementCountAfter: 30,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(!delta.significantDOMChange)
    }

    // MARK: - ActionDelta description

    @Test("Description mentions navigation when URL changed")
    func descriptionURLChanged() {
        let delta = ActionDelta(
            urlChanged: true, newURL: "https://example.com",
            titleChanged: false, newTitle: nil,
            elementCountBefore: 10, elementCountAfter: 10,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(delta.description.contains("navigated"))
    }

    @Test("Description says 'No visible change' when nothing changed")
    func descriptionNoChange() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: 10, elementCountAfter: 10,
            captchaAppeared: false, captchaDisappeared: false
        )
        #expect(delta.description == "No visible change.")
    }

    @Test("Description excludes DOM info when counts are -1")
    func descriptionNegativeCounts() {
        let delta = ActionDelta(
            urlChanged: false, newURL: nil,
            titleChanged: false, newTitle: nil,
            elementCountBefore: -1, elementCountAfter: 50,
            captchaAppeared: false, captchaDisappeared: false
        )
        // With -1 sentinel, significantDOMChange is false, so no DOM message
        #expect(!delta.description.contains("elements"))
    }
}
