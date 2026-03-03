import Foundation

/// All available skills that can appear in a widget pipeline spec.
enum SkillName: String, Codable, CaseIterable {
    // Acquisition skills
    case fetchRedditPosts = "fetch_reddit_posts"
    case fetchCryptoPrice = "fetch_crypto_price"
    case fetchWeather = "fetch_weather"
    case fetchRestApi = "fetch_rest_api"

    // Transform skills
    case sort = "sort"
    case filter = "filter"
    case mapFields = "map_fields"
    case aggregate = "aggregate"

    // Render skills
    case renderList = "render_list"
    case renderStatCard = "render_stat_card"
    case renderChart = "render_chart"
    case renderTable = "render_table"
    case renderComposite = "render_composite"

    /// Whether this skill is a render skill (must be the final step)
    var isRenderSkill: Bool {
        switch self {
        case .renderList, .renderStatCard, .renderChart, .renderTable, .renderComposite:
            return true
        default:
            return false
        }
    }

    /// Whether this skill fetches external data
    var isFetchSkill: Bool {
        switch self {
        case .fetchRedditPosts, .fetchCryptoPrice, .fetchWeather, .fetchRestApi:
            return true
        default:
            return false
        }
    }
}
