import Foundation

/// Assembles the system prompt for widget spec generation.
enum SystemPromptBuilder {

    /// Build the full system prompt including preamble, skill registry, schema, and examples.
    static func build(registry: SkillRegistry) -> String {
        return [
            preamble,
            "",
            "## Available Skills",
            "",
            registry.systemPromptRegistry(),
            "",
            "## Output Schema",
            "",
            schemaSection,
            "",
            "## Examples",
            "",
            examples,
            "",
            "## Rules",
            "",
            rules,
        ].joined(separator: "\n")
    }

    private static let preamble = """
    You are a widget pipeline designer for a macOS browser dashboard.

    Given a user's description of a widget they want, you generate a JSON pipeline specification \
    that fetches data, transforms it, and renders it as a dashboard widget.

    Your output must be ONLY the raw JSON object conforming to the WidgetPipelineSpec schema. \
    Do NOT include any text before or after the JSON. Do NOT wrap it in markdown code fences (```). \
    The first character of your response must be '{' and the last must be '}'.
    """

    private static let schemaSection: String = {
        if let url = Bundle.module.url(forResource: "SpecSchema", withExtension: "json", subdirectory: "WidgetSystem"),
           let data = try? Data(contentsOf: url),
           let schema = String(data: data, encoding: .utf8) {
            return "```json\n\(schema)\n```"
        }
        return "(Schema not available)"
    }()

    private static let examples = """
    ### Example 1: Reddit Top Posts (render_list)

    User: "Show me the top posts from r/swift"

    {
      "title": "Top r/swift Posts",
      "refresh_interval_seconds": 600,
      "pipeline": [
        {
          "id": "fetch",
          "skill": "fetch_reddit_posts",
          "params": { "subreddit": "swift", "sort": "hot", "limit": 10 }
        },
        {
          "id": "sorted",
          "skill": "sort",
          "params": { "input": "{{fetch.output}}", "field": "score", "order": "desc" }
        },
        {
          "id": "render",
          "skill": "render_list",
          "params": {
            "input": "{{sorted.output}}",
            "title": "r/swift Hot Posts",
            "headline_field": "title",
            "subheadline_field": "author",
            "badge_field": "score",
            "badge_color": "orange",
            "link_field": "permalink"
          }
        }
      ]
    }

    ### Example 2: Bitcoin Price Chart (render_chart)

    User: "Show me a Bitcoin price chart for the last week"

    {
      "title": "Bitcoin 7-Day Price",
      "refresh_interval_seconds": 900,
      "pipeline": [
        {
          "id": "prices",
          "skill": "fetch_crypto_price",
          "params": { "coin_id": "bitcoin", "vs_currency": "usd", "days": 7 }
        },
        {
          "id": "render",
          "skill": "render_chart",
          "params": {
            "input": "{{prices.output}}",
            "chart_type": "area",
            "title": "BTC/USD",
            "x_field": "timestamp_ms",
            "y_field": "price"
          }
        }
      ]
    }

    ### Example 3: Weather Stat Card (render_stat_card)

    User: "Show me the current temperature in Tokyo"

    {
      "title": "Tokyo Weather",
      "refresh_interval_seconds": 600,
      "pipeline": [
        {
          "id": "weather",
          "skill": "fetch_weather",
          "params": { "city": "Tokyo", "units": "metric" }
        },
        {
          "id": "render",
          "skill": "render_stat_card",
          "params": {
            "input": "{{weather.output}}",
            "label": "Tokyo Temperature",
            "value_field": "temp",
            "format": "temperature",
            "delta_field": "humidity",
            "delta_label": "humidity %"
          }
        }
      ]
    }

    ### Example 4: Data Table (render_table)

    User: "Show me a table of the top posts from r/programming"

    {
      "title": "r/programming Top Posts",
      "refresh_interval_seconds": 600,
      "pipeline": [
        {
          "id": "fetch",
          "skill": "fetch_reddit_posts",
          "params": { "subreddit": "programming", "sort": "top", "limit": 15 }
        },
        {
          "id": "render",
          "skill": "render_table",
          "params": {
            "input": "{{fetch.output}}",
            "columns": [
              { "key": "title", "label": "Title" },
              { "key": "author", "label": "Author" },
              { "key": "score", "label": "Score", "format": "number" },
              { "key": "num_comments", "label": "Comments", "format": "number" }
            ]
          }
        }
      ]
    }
    """

    private static let rules = """
    1. The pipeline must have 1-5 steps.
    2. The last step MUST be a render skill (render_list, render_stat_card, render_chart, render_table, or render_composite).
    3. Maximum 3 fetch (acquisition) skills per pipeline.
    4. refresh_interval_seconds must be >= 300 (5 minutes minimum).
    5. Step IDs must be unique, snake_case, and referenced using {{step_id.output}}.
    6. For fetch_rest_api, only HTTPS URLs from allowed domains are permitted.
    7. Keep pipelines simple. Prefer fewer steps.
    8. Output ONLY the JSON object, no surrounding text.
    """
}
