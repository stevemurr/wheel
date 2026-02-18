import Foundation

/// Generates CSS for dark mode
struct DarkModeCSS {

    /// Generate the main dark mode CSS with configurable brightness and contrast
    /// Uses a hybrid approach: color-scheme for native elements + filter for content
    static func generate(brightness: Double = 100, contrast: Double = 100) -> String {
        let brightnessValue = brightness / 100.0
        let contrastValue = contrast / 100.0

        // Using :root and higher specificity to ensure our styles win
        return """
        /* Wheel Browser Dark Mode */
        :root[data-wheel-dark="true"] {
            color-scheme: dark !important;
        }

        html[data-wheel-dark="true"],
        html[data-wheel-dark="true"] body {
            min-height: 100% !important;
            background-color: #1a1a1a !important;
        }

        /* Main content filter - applied to body to avoid affecting fixed elements twice */
        html[data-wheel-dark="true"] body {
            filter: invert(1) hue-rotate(180deg) brightness(\(brightnessValue)) contrast(\(contrastValue)) !important;
        }

        /* Un-invert media elements to preserve original colors */
        html[data-wheel-dark="true"] img,
        html[data-wheel-dark="true"] video,
        html[data-wheel-dark="true"] canvas,
        html[data-wheel-dark="true"] picture,
        html[data-wheel-dark="true"] svg image,
        html[data-wheel-dark="true"] [style*="background-image"],
        html[data-wheel-dark="true"] iframe,
        html[data-wheel-dark="true"] embed,
        html[data-wheel-dark="true"] object {
            filter: invert(1) hue-rotate(180deg) !important;
        }

        /* SVG icons often need inversion kept, but photos in SVG need reverting */
        html[data-wheel-dark="true"] svg:not([class*="icon"]):not([class*="logo"]) image {
            filter: invert(1) hue-rotate(180deg) !important;
        }

        /* Handle picture element sources */
        html[data-wheel-dark="true"] picture img,
        html[data-wheel-dark="true"] picture source {
            filter: invert(1) hue-rotate(180deg) !important;
        }

        /* Fix for nested filtered elements - prevent double inversion */
        html[data-wheel-dark="true"] img img,
        html[data-wheel-dark="true"] video video {
            filter: none !important;
        }

        /* Ensure html background covers viewport */
        html[data-wheel-dark="true"]::before {
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
