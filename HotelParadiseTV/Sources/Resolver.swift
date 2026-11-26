import Foundation

/// Zistí priamu adresu videa z oficiálneho prehrávača TV JOJ (media.joj.sk/embed/<id>).
/// Prehrávač má adresu priamo v HTML: `var src = { "mp4": [ "https://…mp4" ] }` (príp. "hls").
enum Resolver {
    static func streamURL(for episode: Episode) async -> URL? {
        if let live = try? await fromEmbed(episode.embed) { return live }
        return URL(string: episode.mp4)
    }

    static func fromEmbed(_ id: String) async throws -> URL? {
        guard let url = URL(string: "https://media.joj.sk/embed/\(id)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("https://www.tv-archiv.sk/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        let html = String(decoding: data, as: UTF8.self)

        for key in ["hls", "mp4"] {
            if let found = firstMatch(in: html, pattern: "\"\(key)\"\\s*:\\s*\\[\\s*\"([^\"]+)\"")
                ?? firstMatch(in: html, pattern: "\"\(key)\"\\s*:\\s*\"([^\"]+)\"") {
                let cleaned = found.replacingOccurrences(of: "\\/", with: "/")
                if let u = URL(string: cleaned), u.scheme?.hasPrefix("http") == true { return u }
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
