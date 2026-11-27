import Foundation

struct Webcam: Codable, Identifiable, Hashable {
    let name: String
    let place: String
    var youtube: String? = nil
    var hls: String? = nil

    var id: String { youtube.map { "yt:" + $0 } ?? ("hls:" + (hls ?? name)) }

    var thumbnail: [URL] {
        guard let y = youtube else { return [] }
        return [URL(string: "https://i.ytimg.com/vi/\(y)/hqdefault_live.jpg"),
                URL(string: "https://i.ytimg.com/vi/\(y)/hqdefault.jpg")].compactMap { $0 }
    }

    /// Text pre vyhľadávanie (bez diakritiky, malými písmenami).
    var searchText: String { (name + " " + place).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
}

struct WebcamGroup: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let region: String
    let cams: [Webcam]
}

struct WebcamCatalog: Codable {
    let version: Int
    let groups: [WebcamGroup]

    var regions: [String] {
        var seen = Set<String>(); var out: [String] = []
        for g in groups where !seen.contains(g.region) { seen.insert(g.region); out.append(g.region) }
        return out
    }
}

/// Zoznam kamier: najprv aktuálny z GitHubu (dá sa opraviť bez novej inštalácie), inak vstavaný.
enum WebcamStore {
    static let remote = URL(string: "https://raw.githubusercontent.com/s6f8ws6nmf-wq/Timecode-Logger/claude/happy-euler-f2tinl/TVArchivTV/Resources/webcams.json")!

    static func bundled() -> WebcamCatalog? {
        guard let url = Bundle.main.url(forResource: "webcams", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WebcamCatalog.self, from: data)
    }

    static func load() async -> WebcamCatalog? {
        let local = bundled()
        var req = URLRequest(url: remote, timeoutInterval: 8)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200,
           let cat = try? JSONDecoder().decode(WebcamCatalog.self, from: data),
           cat.version >= (local?.version ?? 0) {
            return cat
        }
        return local
    }
}

// MARK: - Živé vysielanie

struct LiveChannel: Identifiable, Hashable {
    enum Source: Hashable {
        case stvr(Int)        // www.stvr.sk/json/live5f.json?c=<n>
        case ct(String)       // api.ceskatelevize.cz … channel/<CH_x>
        case hls(String)
    }

    let id: String
    let name: String
    let group: String
    let source: Source

    static let all: [LiveChannel] = [
        LiveChannel(id: "stvr1", name: "Jednotka", group: "STVR", source: .stvr(1)),
        LiveChannel(id: "stvr2", name: "Dvojka", group: "STVR", source: .stvr(2)),
        LiveChannel(id: "stvr24", name: ":24", group: "STVR", source: .stvr(3)),
        LiveChannel(id: "stvrsport", name: "Šport", group: "STVR", source: .stvr(15)),
        LiveChannel(id: "stvrnrsr", name: "NR SR", group: "STVR", source: .stvr(5)),
        LiveChannel(id: "lux", name: "TV Lux", group: "Slovensko", source: .hls("https://stream.tvlux.sk/luxtv/luxtv-livestream/playlist.m3u8")),
        LiveChannel(id: "ct1", name: "ČT1", group: "Česká televize", source: .ct("CH_1")),
        LiveChannel(id: "ct2", name: "ČT2", group: "Česká televize", source: .ct("CH_2")),
        LiveChannel(id: "ct24", name: "ČT24", group: "Česká televize", source: .ct("CH_24")),
        LiveChannel(id: "ctsport", name: "ČT sport", group: "Česká televize", source: .ct("CH_4")),
        LiveChannel(id: "ctd", name: "ČT :D", group: "Česká televize", source: .ct("CH_5")),
        LiveChannel(id: "ctart", name: "ČT art", group: "Česká televize", source: .ct("CH_6"))
    ]

    /// Priama adresa živého streamu + práve vysielaný program (ak ho zdroj poskytuje).
    func resolve() async -> (url: URL, headers: [String: String], now: String?)? {
        switch source {
        case .hls(let s):
            return URL(string: s).map { ($0, [:], nil) }
        case .stvr(let c):
            guard let api = URL(string: "https://www.stvr.sk/json/live5f.json?c=\(c)&b=safari&p=mac&f=0&d=1"),
                  let data = try? await Net.data(api, referer: "https://www.stvr.sk/"),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let clip = obj["clip"] as? [String: Any],
                  let sources = clip["sources"] as? [[String: Any]] else { return nil }
            let hls = sources.first { ($0["type"] as? String ?? "").contains("mpegurl") } ?? sources.first
            guard let src = hls?["src"] as? String, let u = URL(string: src) else { return nil }
            return (u, ["Referer": "https://www.stvr.sk/"], clip["title"] as? String)
        case .ct(let ch):
            guard let api = URL(string: "https://api.ceskatelevize.cz/video/v1/playlist-live/v1/stream-data/channel/\(ch)?canPlayDrm=false&streamType=hls&quality=web&maxQualityCount=5"),
                  let data = try? await Net.data(api, referer: "https://www.ceskatelevize.cz/"),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let urls = obj["streamUrls"] as? [String: Any],
                  let main = urls["main"] as? String, let u = URL(string: main) else { return nil }
            return (u, [:], nil)
        }
    }
}
