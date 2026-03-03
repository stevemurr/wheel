import Testing
import Foundation
@testable import WheelBrowser

@Suite("SkillName")
struct SkillNameTests {

    @Test("All 13 skills are present")
    func allSkills() {
        #expect(SkillName.allCases.count == 13)
    }

    @Test("Render skills identified correctly")
    func renderSkills() {
        let renderSkills = SkillName.allCases.filter(\.isRenderSkill)
        #expect(renderSkills.count == 5)
        #expect(SkillName.renderList.isRenderSkill)
        #expect(SkillName.renderStatCard.isRenderSkill)
        #expect(SkillName.renderChart.isRenderSkill)
        #expect(SkillName.renderTable.isRenderSkill)
        #expect(SkillName.renderComposite.isRenderSkill)
    }

    @Test("Fetch skills identified correctly")
    func fetchSkills() {
        let fetchSkills = SkillName.allCases.filter(\.isFetchSkill)
        #expect(fetchSkills.count == 4)
        #expect(SkillName.fetchRedditPosts.isFetchSkill)
        #expect(SkillName.fetchCryptoPrice.isFetchSkill)
        #expect(SkillName.fetchWeather.isFetchSkill)
        #expect(SkillName.fetchRestApi.isFetchSkill)
    }

    @Test("Transform skills are neither fetch nor render")
    func transformSkills() {
        let transforms: [SkillName] = [.sort, .filter, .mapFields, .aggregate]
        for skill in transforms {
            #expect(!skill.isFetchSkill)
            #expect(!skill.isRenderSkill)
        }
    }

    @Test("Raw values match expected strings")
    func rawValues() {
        #expect(SkillName.fetchRedditPosts.rawValue == "fetch_reddit_posts")
        #expect(SkillName.fetchCryptoPrice.rawValue == "fetch_crypto_price")
        #expect(SkillName.fetchWeather.rawValue == "fetch_weather")
        #expect(SkillName.fetchRestApi.rawValue == "fetch_rest_api")
        #expect(SkillName.sort.rawValue == "sort")
        #expect(SkillName.filter.rawValue == "filter")
        #expect(SkillName.mapFields.rawValue == "map_fields")
        #expect(SkillName.aggregate.rawValue == "aggregate")
        #expect(SkillName.renderList.rawValue == "render_list")
        #expect(SkillName.renderStatCard.rawValue == "render_stat_card")
        #expect(SkillName.renderChart.rawValue == "render_chart")
        #expect(SkillName.renderTable.rawValue == "render_table")
        #expect(SkillName.renderComposite.rawValue == "render_composite")
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for skill in SkillName.allCases {
            let data = try JSONEncoder().encode(skill)
            let decoded = try JSONDecoder().decode(SkillName.self, from: data)
            #expect(decoded == skill)
        }
    }
}
