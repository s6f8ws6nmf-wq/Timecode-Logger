import Foundation

// MARK: - Modely

struct ShowCard: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let title: String
    let info: String
    let image: String?
    var logo: String? = nil

    var imageURL: URL? { image.flatMap { Net.url($0) } }

    /// Odkaz priamo na video (napr. film), nie na stránku relácie.
    var isVideo: Bool { path.split(separator: "/").count >= 2 }

    var slug: String { path.split(separator: "/").first.map(String.init) ?? "" }

    /// Obrázky od najkvalitnejšieho: veľký krajinkový (774×393), potom pôvodný.
    var artwork: [URL] { Artwork.urls(slug: slug, extra: image) }

    var asVideo: VideoItem {
        VideoItem(path: path, title: title, showTitle: info, source: .from(logo: logo))
    }
}

enum Artwork {
    static func urls(slug: String, extra: String?) -> [URL] {
        var out: [URL] = []
        if !slug.isEmpty && !slug.hasPrefix("-") {
            for s in ["\(slug).sk.jpg", "\(slug).cz.jpg"] {
                if let u = Net.url("/images/movies_merged/" + s) { out.append(u) }
            }
        }
        if let extra, let u = Net.url(HTML.unescapeJS(extra)), !out.contains(u) { out.append(u) }
        if !slug.isEmpty, let u = Net.url("/images/movies/\(slug)_landscape.webp"), !out.contains(u) { out.append(u) }
        return out
    }
}

struct HeroItem: Identifiable, Hashable {
    var id: String { video.path }
    let video: VideoItem
    let image: String?
    var artwork: [URL] {
        let slug = video.showPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Artwork.urls(slug: slug, extra: image)
    }
}

struct Shelf: Identifiable, Hashable {
    let id: String
    let items: [ShowCard]
}

struct HomeFeed {
    let hero: [HeroItem]
    let shelves: [Shelf]
}

enum VideoSource: String, Codable, CaseIterable {
    case joj, markiza, nova, stvr, ct, lux, prima, youtube, other

    static func from(logo: String?) -> VideoSource {
        let l = (logo ?? "").lowercased()
        if l.contains("yt") || l.contains("youtube") { return .youtube }
        if l.contains("joj") || l.contains("dajto") || l.contains("wau") { return .joj }
        if l.contains("markiza") || l.contains("doma") { return .markiza }
        if l.contains("nova") { return .nova }
        if l.contains("stvr") || l.contains("rtvs") || l.contains("jednotka") || l.contains("dvojka") || l.contains("stv") { return .stvr }
        if l.contains("ct") || l.contains("decko") { return .ct }
        if l.contains("lux") { return .lux }
        if l.contains("prima") { return .prima }
        return .other
    }

    var name: String {
        switch self {
        case .joj: return "JOJ"
        case .markiza: return "Markíza"
        case .nova: return "Nova"
        case .stvr: return "STVR"
        case .ct: return "ČT"
        case .lux: return "TV Lux"
        case .prima: return "Prima"
        case .youtube: return "YouTube"
        case .other: return ""
        }
    }

    /// Zdroje, ktoré na Apple TV prehrať nevieme (platené / DRM).
    var playable: Bool { self != .prima }
}

struct VideoItem: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let title: String
    let showTitle: String
    let source: VideoSource
    var note: String = ""

    var artwork: [URL] {
        Artwork.urls(slug: showPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")), extra: nil)
    }

    /// Cesta relácie („/farma“) z cesty epizódy („/farma/epizoda-1“).
    var showPath: String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.first.map { "/\($0)" } ?? path
    }
}

struct EpisodeGroup: Identifiable, Hashable {
    let id: String
    let items: [VideoItem]
    var source: VideoSource { items.first?.source ?? .other }
}

struct ShowDetail {
    let card: ShowCard
    let description: String
    let groups: [EpisodeGroup]
}

struct Channel: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let source: VideoSource
}

// MARK: - Načítanie údajov zo stránky

enum Site {
    static let channels: [Channel] = [
        Channel(name: "TV JOJ", path: "/archiv-tv-joj", source: .joj),
        Channel(name: "JOJ Plus", path: "/archiv-tv-joj-plus", source: .joj),
        Channel(name: "JOJ Krimi", path: "/archiv-tv-joj_krimi", source: .joj),
        Channel(name: "Dajto", path: "/archiv-tv-dajto", source: .joj),
        Channel(name: "Markíza", path: "/archiv-tv-markiza", source: .markiza),
        Channel(name: "Doma", path: "/archiv-tv-doma", source: .markiza),
        Channel(name: "Markíza Krimi", path: "/archiv-tv-markiza-krimi", source: .markiza),
        Channel(name: "Markíza Klasik", path: "/archiv-tv-markiza-klasik", source: .markiza),
        Channel(name: "Jednotka", path: "/archiv-tv-jednotka", source: .stvr),
        Channel(name: "Dvojka", path: "/archiv-tv-dvojka", source: .stvr),
        Channel(name: ":24", path: "/archiv-tv-rtvs-24", source: .stvr),
        Channel(name: "TV Lux", path: "/archiv-tv-tv-lux", source: .lux),
        Channel(name: "TA3", path: "/archiv-tv-ta3", source: .other),
        Channel(name: "ČT1", path: "/archiv-tv-ct1", source: .ct),
        Channel(name: "ČT2", path: "/archiv-tv-ct2", source: .ct),
        Channel(name: "ČT :D", path: "/archiv-tv-decko", source: .ct),
        Channel(name: "Nova", path: "/archiv-tv-nova", source: .nova),
        Channel(name: "Nova Cinema", path: "/archiv-tv-nova-cinema", source: .nova),
        Channel(name: "Nova Action", path: "/archiv-tv-nova-action", source: .nova),
        Channel(name: "Nova Lady", path: "/archiv-tv-nova-lady", source: .nova),
        Channel(name: "Prima", path: "/archiv-tv-prima", source: .prima),
        Channel(name: "Óčko", path: "/archiv-tv-ocko", source: .other)
    ]

    static let letters = ["a", "b", "c", "ch", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
                          "n", "o", "p", "r", "s", "t", "u", "v", "w", "x", "z"]

    /// Domovská stránka: pás najnovších epizód + police („Dnes najpozeranejšie seriály“, „Celé filmy“…).
    static func home() async throws -> HomeFeed {
        let html = try await Net.page("/")
        var hero: [HeroItem] = []
        if let start = html.range(of: "ml_archives\">") {
            var block = String(html[start.upperBound...])
            if let end = block.range(of: "ml_list_title") { block = String(block[..<end.lowerBound]) }
            for m in block.components(separatedBy: "<div class=\"ml_movie\">").dropFirst() {
                guard let path = HTML.first("href=\"(/[^\"#]+)\"", in: m) else { continue }
                let img = HTML.first("url\\('([^']+)'\\)", in: m)
                let a = HTML.first("<div class=\"cdiv\">\\s*<a[^>]*>(.*?)</a>", in: m) ?? ""
                let parts = a.components(separatedBy: "<br")
                let show = HTML.text(parts.first ?? "")
                let ep = parts.count > 1 ? HTML.text("<br" + parts.dropFirst().joined(separator: "<br")) : ""
                let logo = HTML.first("logo/([^\"]+)\"", in: m)
                hero.append(HeroItem(video: VideoItem(path: path, title: ep.isEmpty ? show : ep, showTitle: show,
                                                      source: .from(logo: logo)), image: img))
            }
        }
        var shelves: [Shelf] = []
        let skip = ["moje obľúbené", "hrajú v kinách", "seriály"]
        for sec in html.components(separatedBy: "<h2 class=\"ml_list_title\">").dropFirst() {
            let title = HTML.text(HTML.first("^\\s*<a[^>]*>(.*?)</a>", in: sec) ?? HTML.first("^(.*?)</h2>", in: sec) ?? "")
            guard !title.isEmpty, !skip.contains(title.lowercased()) else { continue }
            var cards: [ShowCard] = []
            var seen = Set<String>()
            for m in sec.components(separatedBy: "<div class=\"ml_movie\">").dropFirst() {
                guard let path = HTML.first("class=\"ml_img\"[^>]*href=\"(/[^\"#]+)\"", in: m)
                        ?? HTML.first("href=\"(/[^\"#]+)\"[^>]*class=\"ml_img\"", in: m)
                        ?? HTML.first("href=\"(/[^\"#]+)\"", in: m),
                      !seen.contains(path) else { continue }
                seen.insert(path)
                let img = HTML.first("url\\('([^']+)'\\)", in: m)
                let titleHTML = HTML.first("<div class=\"ml_title\">.*?<a[^>]*>(.*?)</a>", in: m) ?? ""
                let small = HTML.text(HTML.first("<small>(.*?)</small>", in: titleHTML) ?? "")
                let name = HTML.text(HTML.remove("<small>.*?</small>", from: titleHTML))
                guard !name.isEmpty else { continue }
                cards.append(ShowCard(path: path, title: name,
                                      info: small.trimmingCharacters(in: CharacterSet(charactersIn: "() ")),
                                      image: img, logo: HTML.first("logo/([^\"]+)\"", in: m)))
            }
            if !cards.isEmpty { shelves.append(Shelf(id: title, items: cards)) }
        }
        return HomeFeed(hero: hero, shelves: shelves)
    }

    /// Karty relácií na stránkach so zoznamom (stanica, A–Z, žánre…).
    static func shows(at path: String) async throws -> [ShowCard] {
        parseShowCards(try await Net.page(path))
    }

    static func parseShowCards(_ html: String) -> [ShowCard] {
        var seen = Set<String>()
        var out: [ShowCard] = []
        for m in HTML.all("<section class=\"m_tooltip\">(.*?)</section>", in: html) {
            let block = m[1]
            guard let path = HTML.first("<a[^>]*href=\"(/[^\"#]+)\"", in: block), !seen.contains(path) else { continue }
            let image = HTML.first("background-image:\\s*url\\('([^']+)'\\)", in: block)
            let titleHTML = HTML.first("<p class=\"button-style1\">\\s*<a[^>]*>(.*?)</a>", in: block) ?? ""
            let small = HTML.text(HTML.first("<small>(.*?)</small>", in: titleHTML) ?? "")
            var title = HTML.text(HTML.remove("<small>.*?</small>", from: titleHTML))
            if title.isEmpty { title = HTML.text(HTML.first("title=\"([^\"]+)\"", in: block) ?? path) }
            let info = small.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            seen.insert(path)
            out.append(ShowCard(path: path, title: title, info: info, image: image))
        }
        return out
    }

    /// „Najnovšie videá“ – tabuľka posledných pridaných epizód.
    static func latest() async throws -> [VideoItem] {
        let html = try await Net.page("/-najnovsie")
        var out: [VideoItem] = []
        var seen = Set<String>()
        for row in HTML.all("<tr>(.*?)</tr>", in: html) {
            let r = row[1]
            let cells = HTML.all("<td[^>]*>(.*?)</td>", in: r).map { $0[1] }
            guard cells.count >= 3,
                  let link = HTML.all("<a href=\"(/[^\"]+)\"[^>]*>(.*?)</a>", in: r).first,
                  !seen.contains(link[1]) else { continue }
            seen.insert(link[1])
            let logo = HTML.first("logo/([^\"]+)\"", in: r)
            let kind = HTML.text(HTML.remove("<div class=\"tooltip\">.*?</div>", from: cells[1]))
            let when = cells.count >= 5 ? HTML.text(cells[4]) : ""
            out.append(VideoItem(path: link[1], title: HTML.text(link[2]), showTitle: HTML.text(cells[0]),
                                 source: .from(logo: logo),
                                 note: [kind, when].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        return out
    }

    /// Vyhľadávanie (rovnaké ako našepkávač na stránke).
    static func search(_ query: String) async throws -> (shows: [ShowCard], videos: [VideoItem]) {
        var comps = URLComponents(url: Net.base.appendingPathComponent("ajax-search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = comps.url else { return ([], []) }
        let data = try await Net.data(url, referer: Net.base.absoluteString + "/", headers: ["X-Requested-With": "XMLHttpRequest"])
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], []) }
        let shows: [ShowCard] = (obj["results"] as? [[String: Any]] ?? []).compactMap { r in
            guard let path = r["url"] as? String else { return nil }
            let nameHTML = HTML.remove("<div class=\"tooltip\">.*?</div>", from: r["name"] as? String ?? "")
            let title = HTML.text(HTML.first("<span style=\"font-weight: 800;\">(.*?)</span>", in: nameHTML) ?? nameHTML)
            let info = HTML.text(HTML.first("</span>\\s*\\(([^)]*)\\)", in: nameHTML) ?? "")
            return ShowCard(path: path, title: title, info: info, image: r["img"] as? String)
        }
        let videos: [VideoItem] = (obj["videos"] as? [[String: Any]] ?? []).compactMap { v in
            guard let path = v["url"] as? String, path.split(separator: "/").count >= 2 else { return nil }
            let name = HTML.text(v["name"] as? String ?? "")
            let parts = name.components(separatedBy: " - ")
            return VideoItem(path: path, title: parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : name,
                             showTitle: parts.first ?? "", source: .other)
        }
        return (shows, videos)
    }

    /// Detail relácie: popis + zoznam epizód (stránka ho načítava cez /ajax-movie-archive2).
    static func detail(of show: ShowCard) async throws -> ShowDetail {
        let slug = show.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let referer = Net.base.absoluteString + show.path
        async let pageTask = Net.page(show.path)
        async let archiveTask = Net.postForm("/ajax-movie-archive2",
                                             fields: [("name", slug), ("screen_width", "1920"),
                                                      ("container_width", "1200"), ("tab_width", "1200")],
                                             referer: referer)
        let html = (try? await pageTask) ?? ""
        let archive = try await archiveTask

        var title = show.title
        if title.isEmpty || title == show.path {
            title = HTML.text(HTML.first("<meta property=\"og:title\" content=\"([^\"]*)\"", in: html) ?? slug)
        }
        let image = show.image ?? HTML.first("<meta property=\"og:image\" content=\"([^\"]*)\"", in: html)
        var desc = HTML.text(HTML.first("<p itemprop=\"description\">(.*?)</p>", in: html) ?? "")
        if desc.isEmpty {
            desc = HTML.text(HTML.first("<meta name=\"description\" content=\"([^\"]*)\"", in: html) ?? "")
        }
        let card = ShowCard(path: show.path, title: title, info: show.info, image: image)
        return ShowDetail(card: card, description: desc, groups: parseArchive(archive, showTitle: title))
    }

    static func parseArchive(_ data: Data, showTitle: String) -> [EpisodeGroup] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var entries: [[String: Any]] = []
        if let dict = obj["archives"] as? [String: Any] {
            entries = dict["1"] as? [[String: Any]] ?? []
        } else if let arr = obj["archives"] as? [Any], arr.count > 1 {
            entries = arr[1] as? [[String: Any]] ?? []
        }
        var order: [String] = []
        var groups: [String: [VideoItem]] = [:]
        var seen = Set<String>()
        for e in entries {
            let html = e["html"] as? String ?? ""
            guard let a = HTML.all("<a href=\"(/[^\"#]+)\"[^>]*>(.*?)</a>", in: html).first else { continue }
            let path = a[1]
            guard path.split(separator: "/").count >= 2, !path.hasSuffix("/nahlasit"), !seen.contains(path) else { continue }
            var g = HTML.text(e["g"] as? String ?? "")
            if g.lowercased() == "fotografie" { continue }
            if HTML.first("^(\\d{1,2}\\.\\d{1,2}\\.\\d{4}\\s*-)", in: g) != nil { continue } // TV program
            let logo = HTML.first("logo/([^\"]+)\"", in: a[2])
            let title = HTML.text(a[2])
            guard !title.isEmpty else { continue }
            if g.isEmpty { g = "Ostatné" }
            seen.insert(path)
            if groups[g] == nil { order.append(g) }
            groups[g, default: []].append(VideoItem(path: path, title: title, showTitle: showTitle, source: .from(logo: logo)))
        }
        return order.map { EpisodeGroup(id: $0, items: groups[$0] ?? []) }.filter { !$0.items.isEmpty }
    }
}
