import SwiftUI
import WebKit

/// Renders a `RenderInput.chart` using a sandboxed WKWebView with Chart.js.
/// Falls back to a simple text representation when Chart.js is not available.
struct ChartWidgetView: View {
    let config: ChartConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = config.title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            ChartWebViewRepresentable(config: config)
                .frame(minHeight: 200)
        }
    }
}

/// NSViewRepresentable wrapping a sandboxed WKWebView for Chart.js rendering.
struct ChartWebViewRepresentable: NSViewRepresentable {
    let config: ChartConfig

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = buildChartHTML()
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildChartHTML() -> String {
        let labels = config.data.map { row -> String in
            if let ts = row[config.xField] as? Double {
                return "\(Int(ts))"
            }
            return "\(row[config.xField] ?? "")"
        }

        let values = config.data.map { row -> Double in
            if let d = row[config.yField] as? Double { return d }
            if let i = row[config.yField] as? Int { return Double(i) }
            return 0
        }

        let chartType: String
        switch config.type {
        case .line: chartType = "line"
        case .bar: chartType = "bar"
        case .area: chartType = "line"
        case .scatter: chartType = "scatter"
        case .pie: chartType = "pie"
        case .doughnut: chartType = "doughnut"
        case .candlestick: chartType = "bar"
        }

        let fillOption = config.type == .area ? "true" : "false"
        let labelsJSON = (try? JSONSerialization.data(withJSONObject: labels)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let valuesJSON = (try? JSONSerialization.data(withJSONObject: values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let accentColor = config.colorScheme ?? "#007AFF"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                background: transparent;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                overflow: hidden;
            }
            #chart-container { width: 100%; height: 100vh; padding: 8px; }
            canvas { width: 100% !important; height: 100% !important; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
        </head>
        <body>
        <div id="chart-container">
            <canvas id="chart"></canvas>
        </div>
        <script>
        (function() {
            const ctx = document.getElementById('chart').getContext('2d');
            new Chart(ctx, {
                type: '\(chartType)',
                data: {
                    labels: \(labelsJSON),
                    datasets: [{
                        label: '\(config.title ?? "")',
                        data: \(valuesJSON),
                        borderColor: '\(accentColor)',
                        backgroundColor: '\(accentColor)33',
                        fill: \(fillOption),
                        tension: 0.3,
                        borderWidth: 2,
                        pointRadius: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: { display: false },
                        tooltip: { enabled: true }
                    },
                    scales: {
                        x: {
                            display: true,
                            grid: { display: false },
                            ticks: { maxTicksLimit: 6, font: { size: 10 } }
                        },
                        y: {
                            display: true,
                            grid: { color: 'rgba(128,128,128,0.1)' },
                            ticks: { maxTicksLimit: 5, font: { size: 10 } }
                        }
                    }
                }
            });
        })();
        </script>
        </body>
        </html>
        """
    }
}
