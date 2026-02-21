import Foundation

/// Generates CSS for dark mode
struct DarkModeCSS {

    /// Generate the main dark mode CSS with configurable brightness and contrast
    /// Uses a hybrid approach: color-scheme for native elements + filter for content
    /// The data-wheel-dark-mode attribute controls which approach is used:
    /// - "native": Site has native dark mode support, just set color-scheme
    /// - "filter": Apply invert filter for sites without native support
    static func generate(brightness: Double = 100, contrast: Double = 100) -> String {
        let brightnessValue = brightness / 100.0
        let contrastValue = contrast / 100.0

        // Using :root and higher specificity to ensure our styles win
        return """
        /* Wheel Browser Dark Mode */

        /* Native dark mode - just enable color-scheme, let site handle the rest */
        :root[data-wheel-dark="true"][data-wheel-dark-mode="native"] {
            color-scheme: dark !important;
        }

        /* Filter-based dark mode - for sites without native support */
        :root[data-wheel-dark="true"][data-wheel-dark-mode="filter"] {
            color-scheme: dark !important;
        }

        /* Dark background on html only - this won't be inverted */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] {
            min-height: 100% !important;
            background-color: #1a1a1a !important;
        }

        /* Body gets the invert filter - its white background will become dark */
        /* Don't set background here, let the filter invert the page's natural background */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] body {
            min-height: 100% !important;
            filter: invert(1) hue-rotate(180deg) brightness(\(brightnessValue)) contrast(\(contrastValue)) !important;
        }

        /* Un-invert media elements to preserve original colors */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] img,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] video,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] canvas,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] picture,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] svg image,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] [style*="background-image"],
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] iframe,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] embed,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] object {
            filter: invert(1) hue-rotate(180deg) !important;
        }

        /* SVG icons often need inversion kept, but photos in SVG need reverting */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] svg:not([class*="icon"]):not([class*="logo"]) image {
            filter: invert(1) hue-rotate(180deg) !important;
        }

        /* Handle picture element sources */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] picture img,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] picture source {
            filter: invert(1) hue-rotate(180deg) !important;
        }

        /* Fix for nested filtered elements - prevent double inversion */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] img img,
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"] video video {
            filter: none !important;
        }

        /* Ensure html background covers viewport for filter mode */
        html[data-wheel-dark="true"][data-wheel-dark-mode="filter"]::before {
            content: "";
            position: fixed;
            top: 0;
            left: 0;
            width: 100vw;
            height: 100vh;
            background-color: #1a1a1a;
            z-index: -2147483647;
            pointer-events: none;
        }
        """
    }

    /// Generate minified CSS
    static func generateMinified(brightness: Double = 100, contrast: Double = 100) -> String {
        // More robust minification that handles multi-line comments properly
        var css = generate(brightness: brightness, contrast: contrast)

        // Remove multi-line comments
        while let startRange = css.range(of: "/*"),
              let endRange = css.range(of: "*/", range: startRange.upperBound..<css.endIndex) {
            css.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }

        // Collapse whitespace
        return css
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " {", with: "{")
            .replacingOccurrences(of: "{ ", with: "{")
            .replacingOccurrences(of: " }", with: "}")
            .replacingOccurrences(of: "; ", with: ";")
    }
}
