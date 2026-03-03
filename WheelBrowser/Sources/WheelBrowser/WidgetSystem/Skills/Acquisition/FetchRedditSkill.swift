import Foundation

/// Fetches posts from a Reddit subreddit via the public JSON API.
struct FetchRedditSkill: WidgetSkill {
    let name = SkillName.fetchRedditPosts

    let paramSchema = """
    {
      "subreddit": "string (required) — e.g. 'swift', 'programming'",
      "sort": "string (optional, default 'hot') — one of: hot, new, top, rising",
      "limit": "integer (optional, default 10, max 25) — number of posts to fetch"
    }
    """

    func execute(params: [String: Any]) async throws -> Any {
        guard let subreddit = params["subreddit"] as? String, !subreddit.isEmpty else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.missing("subreddit"))
        }

        let sort = (params["sort"] as? String) ?? "hot"
        let limit = min((params["limit"] as? Int) ?? 10, 25)

        let urlString = "https://www.reddit.com/r/\(subreddit)/\(sort).json?limit=\(limit)&raw_json=1"
        guard let url = URL(string: urlString) else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillParamError.invalid("subreddit", subreddit))
        }

        var request = URLRequest(url: url)
        request.setValue("WheelBrowser/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.badStatus(code))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let children = dataObj["children"] as? [[String: Any]] else {
            throw WidgetError.executionFailed(stepId: "", underlying: SkillHTTPError.parseError)
        }

        return children.compactMap { child -> [String: Any]? in
            guard let post = child["data"] as? [String: Any] else { return nil }
            return [
                "title": post["title"] as? String ?? "",
                "author": post["author"] as? String ?? "[deleted]",
                "score": post["score"] as? Int ?? 0,
                "num_comments": post["num_comments"] as? Int ?? 0,
                "url": post["url"] as? String ?? "",
                "permalink": "https://reddit.com\(post["permalink"] as? String ?? "")",
                "created_utc": post["created_utc"] as? Double ?? 0,
                "subreddit": post["subreddit"] as? String ?? subreddit,
                "is_self": post["is_self"] as? Bool ?? false,
            ]
        }
    }
}
