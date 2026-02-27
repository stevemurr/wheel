import Testing
import Foundation
@testable import WheelBrowser

@Suite("Date+RelativeTime Tests")
struct DateRelativeTimeTests {

    // MARK: - relativeTimeString() Tests

    @Test("Less than 60 seconds returns 'now'")
    func lessThan60SecondsReturnsNow() {
        let date = Date().addingTimeInterval(-30) // 30 seconds ago
        #expect(date.relativeTimeString() == "now")
    }

    @Test("Exactly at 59 seconds returns 'now'")
    func at59SecondsReturnsNow() {
        let date = Date().addingTimeInterval(-59)
        #expect(date.relativeTimeString() == "now")
    }

    @Test("1 minute returns '1m ago'")
    func oneMinuteReturns1mAgo() {
        let date = Date().addingTimeInterval(-60) // 1 minute ago
        #expect(date.relativeTimeString() == "1m ago")
    }

    @Test("5 minutes returns '5m ago'")
    func fiveMinutesReturns5mAgo() {
        let date = Date().addingTimeInterval(-300) // 5 minutes ago
        #expect(date.relativeTimeString() == "5m ago")
    }

    @Test("59 minutes returns '59m ago'")
    func fiftyNineMinutesReturns59mAgo() {
        let date = Date().addingTimeInterval(-3540) // 59 minutes ago
        #expect(date.relativeTimeString() == "59m ago")
    }

    @Test("1 hour returns '1h ago'")
    func oneHourReturns1hAgo() {
        let date = Date().addingTimeInterval(-3600) // 1 hour ago
        #expect(date.relativeTimeString() == "1h ago")
    }

    @Test("3 hours returns '3h ago'")
    func threeHoursReturns3hAgo() {
        let date = Date().addingTimeInterval(-10800) // 3 hours ago
        #expect(date.relativeTimeString() == "3h ago")
    }

    @Test("23 hours returns '23h ago'")
    func twentyThreeHoursReturns23hAgo() {
        let date = Date().addingTimeInterval(-82800) // 23 hours ago
        #expect(date.relativeTimeString() == "23h ago")
    }

    @Test("1 day returns '1d ago'")
    func oneDayReturns1dAgo() {
        let date = Date().addingTimeInterval(-86400) // 1 day ago
        #expect(date.relativeTimeString() == "1d ago")
    }

    @Test("2 days returns '2d ago'")
    func twoDaysReturns2dAgo() {
        let date = Date().addingTimeInterval(-172800) // 2 days ago
        #expect(date.relativeTimeString() == "2d ago")
    }

    @Test("6 days returns '6d ago'")
    func sixDaysReturns6dAgo() {
        let date = Date().addingTimeInterval(-518400) // 6 days ago
        #expect(date.relativeTimeString() == "6d ago")
    }

    @Test("7+ days returns formatted date")
    func sevenPlusDaysReturnsFormattedDate() {
        let date = Date().addingTimeInterval(-604800) // 7 days ago
        let result = date.relativeTimeString()

        // Should not be one of the relative formats
        #expect(!result.hasSuffix("ago"))
        #expect(result != "now")

        // Should contain some date-like content (numbers, slashes, or dashes)
        #expect(result.contains("/") || result.contains("-") || result.contains(",") || result.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    @Test("Very old date returns formatted date")
    func veryOldDateReturnsFormattedDate() {
        let date = Date().addingTimeInterval(-31536000) // 1 year ago
        let result = date.relativeTimeString()

        // Should not be a relative format
        #expect(!result.hasSuffix("ago"))
        #expect(result != "now")
    }

    // MARK: - Edge Cases

    @Test("Future date returns 'now'")
    func futureDateReturnsNow() {
        // Dates in the future will have negative intervals
        // The function uses interval < 60 which includes negative numbers
        let futureDate = Date().addingTimeInterval(30) // 30 seconds in future
        #expect(futureDate.relativeTimeString() == "now")
    }

    @Test("Current date returns 'now'")
    func currentDateReturnsNow() {
        let date = Date()
        #expect(date.relativeTimeString() == "now")
    }

    // MARK: - abbreviatedRelativeTimeString() Tests

    @Test("abbreviatedRelativeTimeString returns system-formatted string")
    func abbreviatedRelativeTimeReturnsSystemFormat() {
        let date = Date().addingTimeInterval(-7200) // 2 hours ago
        let result = date.abbreviatedRelativeTimeString()

        // Just verify it returns something non-empty
        // The exact format depends on locale
        #expect(!result.isEmpty)
    }
}
